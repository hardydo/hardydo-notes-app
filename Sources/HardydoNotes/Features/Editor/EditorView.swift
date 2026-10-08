import AppKit
import HardydoNotesCore
import SwiftUI

struct EditorView: NSViewRepresentable {
    let text: String
    let language: ContentLanguage
    let isEditable: Bool
    let zoom: CGFloat
    var highlights: [NSRange] = []
    var currentHighlight: NSRange?
    let controller: EditorController
    var onEscape: () -> Bool = { false }
    var onEdit: () -> Void = {}
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onEdit: onEdit, onEscape: onEscape, zoom: zoom, language: language)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = Self.makeTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        MarkdownTheme.applyInsets(to: textView, zoom: zoom)
        textView.font = MarkdownTheme.baseFont(zoom)
        textView.typingAttributes = MarkdownTheme.baseAttributes(zoom)
        textView.string = text
        textView.isEditable = isEditable
        context.coordinator.folds = textView.folds
        textView.folds.zoom = zoom
        textView.textStorage?.delegate = context.coordinator
        textView.delegate = context.coordinator
        MarkdownTheme.restyle(textView.textStorage!, zoom: zoom)
        controller.attach(textView, commit: context.coordinator.commit)
        context.coordinator.colorSyntaxNow(textView)
        let ruler = LineNumberRuler(textView: textView, scrollView: scrollView, zoom: zoom)
        textView.folds.onChange = { [weak ruler] in ruler?.needsDisplay = true }
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        if text.isEmpty, isEditable {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onEdit = onEdit
        context.coordinator.onEscape = onEscape
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        controller.attach(textView, commit: context.coordinator.commit)
        if context.coordinator.zoom != zoom {
            context.coordinator.zoom = zoom
            MarkdownTheme.applyInsets(to: textView, zoom: zoom)
            (scrollView.verticalRulerView as? LineNumberRuler)?.zoom = zoom
            textView.folds.zoom = zoom
            textView.typingAttributes = MarkdownTheme.baseAttributes(zoom)
            MarkdownTheme.restyle(textView.textStorage!, zoom: zoom)
        }
        // Typing reaches the store after a pause, so until then the editor holds the newer text.
        if !context.coordinator.hasPendingEdit, !textView.hasMarkedText(), textView.string != text {
            let selection = textView.selectedRange()
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            // shouldChangeText refuses edits on a non-editable view, so unlock while applying text that changed outside the editor.
            textView.isEditable = true
            context.coordinator.isApplyingExternalText = true
            defer { context.coordinator.isApplyingExternalText = false }
            if textView.shouldChangeText(in: full, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: full, with: text)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
                context.coordinator.appliedHighlights = nil
            }
        }
        textView.isEditable = isEditable
        if context.coordinator.language != language {
            context.coordinator.language = language
            context.coordinator.colorSyntax(textView, delay: .zero)
        }
        context.coordinator.highlight(textView, highlights, current: currentHighlight)
        if let range = controller.pendingReveal, NSMaxRange(range) <= (textView.string as NSString).length {
            controller.pendingReveal = nil
            let controller = controller
            DispatchQueue.main.async { controller.reveal(range) }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.commit()
    }

    // TextKit 1, because the line-number gutter reads line positions from the layout manager.
    private static func makeTextView() -> (NSScrollView, CodeTextView) {
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

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var onChange: (String) -> Void
        var onEdit: () -> Void
        var onEscape: () -> Bool
        var zoom: CGFloat
        var appliedHighlights: (ranges: [NSRange], current: NSRange?)?
        /// Text arriving from the store (a change on disk or a JSON tidy-up) is not a user edit.
        var isApplyingExternalText = false
        var language: ContentLanguage
        weak var folds: FoldState?
        private let undoManager: UndoManager
        private var syntaxTask: Task<Void, Never>?
        private var tokenizing: Task<([SyntaxToken], [FoldRegion]), Never>?
        private var pendingEdit: Task<Void, Never>?
        private weak var editedView: NSTextView?
        private static let syntaxLimit = 512_000
        private static let instantColorLimit = 100_000
        private static let commitDelay = Duration.milliseconds(250)

        var hasPendingEdit: Bool { pendingEdit != nil }

        @MainActor
        init(onChange: @escaping (String) -> Void, onEdit: @escaping () -> Void, onEscape: @escaping () -> Bool, zoom: CGFloat, language: ContentLanguage) {
            self.onChange = onChange
            self.onEdit = onEdit
            self.onEscape = onEscape
            self.zoom = zoom
            self.language = language
            undoManager = UndoManager()
        }

        /*
         Tokens are found off the main thread and drawn as temporary attributes, which change neither the text, its layout nor undo.
         A regex pass cannot be stopped midway, so a new pass waits for the running one and only the latest request goes ahead.
         */
        @MainActor
        func colorSyntax(_ textView: NSTextView, delay: Duration? = nil) {
            syntaxTask?.cancel()
            let text = textView.string
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
                    let work = Task.detached(priority: .userInitiated) {
                        let tokens = SyntaxHighlighter.tokens(in: text, language: language)
                        return (tokens, CodeFolding.regions(in: text, language: language, tokens: tokens))
                    }
                    self.tokenizing = work
                    (tokens, regions) = await work.value
                }
                // A composing input method calls back with the committed text, which colours it again.
                guard !Task.isCancelled, let textView, textView.string == text, !textView.hasMarkedText() else { return }
                Self.apply(tokens, regions, to: textView)
            }
        }

        // A new editor is coloured before its first frame, so switching back from the preview never shows plain text.
        @MainActor
        func colorSyntaxNow(_ textView: NSTextView) {
            let text = textView.string
            guard (text as NSString).length <= Self.instantColorLimit else { return colorSyntax(textView, delay: .zero) }
            let tokens = SyntaxHighlighter.tokens(in: text, language: language)
            Self.apply(tokens, CodeFolding.regions(in: text, language: language, tokens: tokens), to: textView)
        }

        @MainActor
        private static func apply(_ tokens: [SyntaxToken], _ regions: [FoldRegion], to textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let length = (textView.string as NSString).length
            let full = NSRange(location: 0, length: length)
            for key in SyntaxTheme.keys {
                layoutManager.removeTemporaryAttribute(key, forCharacterRange: full)
            }
            for token in tokens where NSMaxRange(token.range) <= length {
                layoutManager.addTemporaryAttributes(SyntaxTheme.attributes(token.kind), forCharacterRange: token.range)
            }
            (textView as? CodeTextView)?.folds.setRegions(regions)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        // Temporary attributes colour the matches without touching the text or its undo history.
        @MainActor
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
            if editedMask.contains(.editedCharacters) {
                MarkdownTheme.restyle(textStorage, zoom: zoom, range: textStorage.editedRange)
                let folds = folds
                MainActor.assumeIsolated { folds?.textEdited(range, changeInLength: delta) }
            }
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

        // Like VS Code, a new line starts at the indentation of the line it was split from.
        @MainActor
        private func insertNewlineKeepingIndent(_ textView: NSTextView) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let text = textView.string as NSString
            let selection = textView.selectedRange()
            let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
            var end = lineStart
            while end < selection.location, [9, 32].contains(text.character(at: end)) { end += 1 }
            guard end > lineStart else { return false }
            textView.insertText("\n" + text.substring(with: NSRange(location: lineStart, length: end - lineStart)), replacementRange: selection)
            return true
        }

        /*
         The store hears about typing after a short pause rather than per keystroke, since every store change
         redraws the sidebar, tabs and menus; anything that reads the text first calls `commit`.
         */
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.typingAttributes = MarkdownTheme.baseAttributes(zoom)
            colorSyntax(textView)
            guard !textView.hasMarkedText(), !isApplyingExternalText else { return }
            onEdit()
            editedView = textView
            scheduleCommit()
        }

        @MainActor
        private func scheduleCommit() {
            pendingEdit?.cancel()
            pendingEdit = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.commitDelay)
                guard !Task.isCancelled, let self else { return }
                // Mid-composition (Telex, pinyin…) the text is not final yet; wait for the input method instead of dropping it.
                if self.editedView?.hasMarkedText() == true { return self.scheduleCommit() }
                self.commit()
            }
        }

        @MainActor
        func commit() {
            guard pendingEdit != nil else { return }
            pendingEdit?.cancel()
            pendingEdit = nil
            if let editedView { onChange(editedView.string) }
        }
    }
}
