import AppKit
import HardydoNotesCore

/*
 One open tab's editor: its text view, undo history, folds and colours. Sessions outlive the SwiftUI view, so
 switching tabs swaps views instead of rebuilding them.
 */
@MainActor
final class EditorSession: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    let scrollView: EditorScrollView
    let textView: CodeTextView
    var onChange: (String) -> Int?
    var onEdit: () -> Void
    var onEscape: () -> Bool
    var zoom: CGFloat
    var appliedHighlights: (ranges: [NSRange], current: NSRange?)?
    /// Text arriving from the store (a change on disk or a JSON tidy-up) is not a user edit.
    var isApplyingExternalText = false
    var language: ContentLanguage
    var syncedRevision: Int
    weak var controller: EditorController?
    /// Set for a new empty note, which takes the keyboard as soon as it shows.
    let wantsFocus: Bool
    private var editCount = 0
    /// The colours on screen, and how much of the text at each end no edit has touched since they were applied.
    private var applied: (tokens: [SyntaxToken], length: Int)?
    private var unchangedPrefix = Int.max
    private var unchangedSuffix = Int.max
    private var pendingSince: ContinuousClock.Instant?
    private let undoManager: UndoManager
    private var syntaxTask: Task<Void, Never>?
    private var tokenizing: Task<([SyntaxToken], [FoldRegion]), Never>?
    private var pendingEdit: Task<Void, Never>?
    private weak var editedView: NSTextView?
    private static let syntaxLimit = 512_000
    private static let instantColorLimit = 100_000
    // Regexes and fold scans slow down badly on one huge line, such as minified JSON.
    private nonisolated static let longLineLimit = 20_000
    private static let commitDelay = Duration.milliseconds(250)
    private static let commitCap = Duration.seconds(3)

    var hasPendingEdit: Bool { pendingEdit != nil }

    init(text: NoteText, language: ContentLanguage, isEditable: Bool, zoom: CGFloat, controller: EditorController) {
        onChange = { _ in nil }
        onEdit = {}
        onEscape = { false }
        self.zoom = zoom
        self.language = language
        self.controller = controller
        syncedRevision = text.revision
        wantsFocus = text.string.isEmpty && isEditable
        undoManager = UndoManager()
        (scrollView, textView) = Self.makeTextView()
        super.init()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        EditorTheme.applyInsets(to: textView, zoom: zoom)
        textView.font = EditorTheme.baseFont(zoom)
        textView.typingAttributes = EditorTheme.baseAttributes(zoom)
        textView.string = text.string
        textView.reindexLines()
        textView.isEditable = isEditable
        textView.folds.zoom = zoom
        textView.textStorage?.delegate = self
        textView.delegate = self
        EditorTheme.restyle(textView.textStorage!, zoom: zoom)
        colorSyntaxNow(textView)
        let ruler = LineNumberRuler(textView: textView, scrollView: scrollView, zoom: zoom)
        textView.folds.onChange = { [weak ruler] in ruler?.needsDisplay = true }
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }

    // TextKit 1, because the line-number gutter reads line positions from the layout manager.
    private static func makeTextView() -> (EditorScrollView, CodeTextView) {
        let scrollView = EditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = ThinScroller()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        let textView = CodeTextView(usingTextLayoutManager: false)
        textView.folds.textView = textView
        textView.layoutManager?.delegate = textView.folds
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    /// Brings the view up to date with the note and settings it shows now.
    func update(text: NoteText, language: ContentLanguage, isEditable: Bool, zoom: CGFloat, highlights: [NSRange], currentHighlight: NSRange?) {
        if self.zoom != zoom {
            self.zoom = zoom
            EditorTheme.applyInsets(to: textView, zoom: zoom)
            (scrollView.verticalRulerView as? LineNumberRuler)?.zoom = zoom
            textView.folds.zoom = zoom
            textView.typingAttributes = EditorTheme.baseAttributes(zoom)
            EditorTheme.restyle(textView.textStorage!, zoom: zoom)
        }
        // Typing reaches the store after a pause, so until then the editor holds the newer text.
        if text.revision != syncedRevision, !hasPendingEdit, !textView.hasMarkedText() {
            syncedRevision = text.revision
            replaceText(of: textView, with: text.string)
        }
        textView.isEditable = isEditable
        if self.language != language {
            self.language = language
            colorSyntax(textView, delay: .zero)
        }
        highlight(textView, highlights, current: currentHighlight)
    }

    // Text that changed outside the editor, such as on disk, compared only once per new revision.
    func replaceText(of textView: NSTextView, with text: String) {
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        // shouldChangeText refuses edits on a non-editable view, so unlock while applying text that changed outside the editor.
        textView.isEditable = true
        isApplyingExternalText = true
        defer { isApplyingExternalText = false }
        guard textView.shouldChangeText(in: full, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: full, with: text)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        appliedHighlights = nil
    }

    /*
     Tokens are found off the main thread and drawn as temporary attributes, which change neither the text, its layout nor undo.
     A regex pass cannot be stopped midway, so a new pass waits for the running one and only the latest request goes ahead.
     */
    func colorSyntax(_ textView: NSTextView, delay: Duration? = nil) {
        syntaxTask?.cancel()
        let text = textView.string
        let lines = (textView as? CodeTextView)?.lines
        let edits = editCount
        let language = language
        let length = (text as NSString).length
        let delay = delay ?? (length > 100_000 ? .milliseconds(400) : .milliseconds(120))
        syntaxTask = Task { [weak textView] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            _ = await self.tokenizing?.value
            guard !Task.isCancelled else { return }
            var tokens: [SyntaxToken] = []
            var regions: [FoldRegion] = []
            if length <= Self.syntaxLimit {
                let work = Task.detached(priority: .userInitiated) { Self.tokenize(text, language: language, lines: lines) }
                self.tokenizing = work
                (tokens, regions) = await work.value
            }
            // A composing input method calls back with the committed text, which colours it again.
            guard !Task.isCancelled, let textView, self.editCount == edits, !textView.hasMarkedText() else { return }
            self.apply(tokens, regions, to: textView)
        }
    }

    private nonisolated static func tokenize(_ text: String, language: ContentLanguage, lines: LineIndex?) -> ([SyntaxToken], [FoldRegion]) {
        if let lines, lines.maxLineLength(textLength: (text as NSString).length) > longLineLimit { return ([], []) }
        let tokens = SyntaxHighlighter.tokens(in: text, language: language)
        return (tokens, CodeFolding.regions(in: text, language: language, tokens: tokens))
    }

    // A new editor is coloured before its first frame, so switching back from the preview never shows plain text.
    func colorSyntaxNow(_ textView: NSTextView) {
        let text = textView.string
        guard (text as NSString).length <= Self.instantColorLimit else { return colorSyntax(textView, delay: .zero) }
        let (tokens, regions) = Self.tokenize(text, language: language, lines: (textView as? CodeTextView)?.lines)
        apply(tokens, regions, to: textView)
    }

    // Clipping each token to the redone span keeps overlapping tokens layered exactly as a full pass would.
    private func apply(_ tokens: [SyntaxToken], _ regions: [FoldRegion], to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        let span = applied.map {
            TokenDiff.changedSpan(old: $0.tokens, new: tokens, oldLength: $0.length, newLength: length, unchangedPrefix: unchangedPrefix, unchangedSuffix: unchangedSuffix)
        } ?? (tokens.isEmpty ? nil : NSRange(location: 0, length: length))
        if let span {
            for key in SyntaxTheme.keys {
                layoutManager.removeTemporaryAttribute(key, forCharacterRange: span)
            }
            for token in tokens where NSMaxRange(token.range) <= length {
                let clipped = NSIntersectionRange(token.range, span)
                if clipped.length > 0 { layoutManager.addTemporaryAttributes(SyntaxTheme.attributes(token.kind), forCharacterRange: clipped) }
            }
        }
        applied = (tokens, length)
        unchangedPrefix = .max
        unchangedSuffix = .max
        (textView as? CodeTextView)?.folds.setRegions(regions)
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }

    // Temporary attributes colour the matches without touching the text or its undo history.
    func highlight(_ textView: NSTextView, _ ranges: [NSRange], current: NSRange?) {
        if let appliedHighlights, appliedHighlights.ranges == ranges, appliedHighlights.current == current { return }
        // Matches come from the stored text, which lags behind while an input method is still composing.
        guard !textView.hasMarkedText() else { return }
        guard let layoutManager = textView.layoutManager else { return }
        let length = (textView.string as NSString).length
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        for range in ranges where NSMaxRange(range) <= length {
            let color = range == current ? NSColor.systemOrange.withAlphaComponent(0.55) : NSColor.systemYellow.withAlphaComponent(0.3)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
        appliedHighlights = (ranges, current)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        editCount &+= 1
        unchangedPrefix = min(unchangedPrefix, range.location)
        unchangedSuffix = min(unchangedSuffix, textStorage.length - NSMaxRange(range))
        EditorTheme.restyle(textStorage, zoom: zoom, range: textStorage.editedRange)
        let lines = textView.updateLines(edited: range, delta: delta)
        textView.folds.textEdited(range, changeInLength: delta, lines: lines)
    }

    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        (textView as? CodeTextView)?.folds.adjustSelection(from: old, to: new) ?? new
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): onEscape()
        case #selector(NSResponder.insertNewline(_:)): insertNewlineKeepingIndent(textView)
        default: false
        }
    }

    private func insertNewlineKeepingIndent(_ textView: NSTextView) -> Bool {
        guard !textView.hasMarkedText(), let edit = LineEditing.newlineKeepingIndent(textView.string, selection: textView.selectedRange()) else { return false }
        textView.breakUndoCoalescing()
        textView.insertText(edit.replacement, replacementRange: edit.range)
        return true
    }

    /*
     The store hears about typing after a short pause rather than per keystroke, since every store change
     redraws the sidebar, tabs and menus; anything that reads the text first calls `commit`.
     */
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        textView.typingAttributes = EditorTheme.baseAttributes(zoom)
        colorSyntax(textView)
        guard !textView.hasMarkedText(), !isApplyingExternalText else { return }
        onEdit()
        editedView = textView
        scheduleCommit()
    }

    // Steady typing still reaches the store every few seconds, so a crash or a reader of the store never lags far behind.
    private func scheduleCommit(after wait: Duration? = nil) {
        pendingEdit?.cancel()
        let since = pendingSince ?? .now
        pendingSince = since
        let delay = wait ?? min(Self.commitDelay, max(.zero, Self.commitCap - (ContinuousClock.now - since)))
        pendingEdit = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Mid-composition (Telex, pinyin…) the text is not final yet; wait for the input method instead of dropping it.
            if self.editedView?.hasMarkedText() == true { return self.scheduleCommit(after: Self.commitDelay) }
            self.commit()
        }
    }

    func commit() {
        guard pendingEdit != nil else { return }
        pendingEdit?.cancel()
        pendingEdit = nil
        pendingSince = nil
        if let editedView, let revision = onChange(editedView.string) {
            syncedRevision = revision
        }
    }
}
