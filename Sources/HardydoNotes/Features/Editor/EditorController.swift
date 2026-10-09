import AppKit
import HardydoNotesCore
import Observation

enum FormatAction {
    case wrap(String)
    case line(LinePrefix)
    case link
    case table(rows: Int, columns: Int)
    case rule
}

@MainActor
@Observable
final class EditorController {
    @ObservationIgnored private(set) weak var textView: NSTextView?
    @ObservationIgnored private var commitPending: () -> Void = {}
    /// A match to show once the editor for a newly selected note exists.
    @ObservationIgnored var pendingReveal: NSRange?
    /// Editing shortcuts only act while typing in the editor, never on the note behind a search or rename field.
    private(set) var hasFocus = false
    /// The 0-based line holding the caret, published only when it changes line.
    private(set) var caretLine = 0

    var lineCount: Int? {
        (textView as? CodeTextView)?.lines.count
    }

    @ObservationIgnored private var sessions: [Note.ID: EditorSession] = [:]

    func session(for note: Note.ID, make: () -> EditorSession) -> EditorSession {
        if let session = sessions[note] { return session }
        let session = make()
        sessions[note] = session
        return session
    }

    /// Frees the editors of tabs that closed; each keeps its undo history only while its tab is open.
    func keepSessions(for notes: some Sequence<Note.ID>) {
        let open = Set(notes)
        for (note, session) in sessions where !open.contains(note) {
            session.commit()
            detach(session.textView)
            sessions[note] = nil
        }
    }

    func detach(_ textView: CodeTextView) {
        guard self.textView === textView else { return }
        self.textView = nil
        commitPending = {}
    }

    func attach(_ textView: CodeTextView, commit: @escaping () -> Void) {
        self.textView = textView
        commitPending = commit
        textView.onFocusChange = { [weak self] focused in
            // Focus moves while views are being rebuilt; the menus catch up right after.
            Task { @MainActor in
                if self?.hasFocus != focused { self?.hasFocus = focused }
            }
        }
        textView.onCaretMove = { [weak self, weak textView] _ in
            Task { @MainActor in
                guard let line = textView?.caretLine, self?.caretLine != line else { return }
                self?.caretLine = line
            }
        }
        textView.onCaretMove(textView.selectedRange().location)
        scrollView?.onScroll = { [weak self] in self?.onScroll() }
    }

    @ObservationIgnored var onScroll: () -> Void = {}

    private var scrollView: EditorScrollView? {
        textView?.enclosingScrollView as? EditorScrollView
    }

    var topLine: Double? {
        scrollView?.topLine
    }

    func scroll(toLine line: Double) {
        scrollView?.follow(line)
    }

    /// Hands typing that is still waiting for its pause to the store.
    func commit() {
        commitPending()
    }

    var selectedRange: NSRange? {
        textView?.selectedRange()
    }

    var selectedText: String? {
        guard let textView, let range = selectedRange, range.length > 0 else { return nil }
        return (textView.string as NSString).substring(with: range)
    }

    func reveal(_ range: NSRange) {
        guard let textView, NSMaxRange(range) <= (textView.string as NSString).length else { return }
        folds?.unfold(intersecting: range)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    private var folds: FoldState? {
        (textView as? CodeTextView)?.folds
    }

    func fold() { folds?.foldAtCaret() }
    func unfold() { folds?.unfoldAtCaret() }
    func foldAll() { folds?.foldAll() }
    func unfoldAll() { folds?.unfoldAll() }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    @discardableResult
    func replace(_ range: NSRange, with text: String) -> Bool {
        guard let textView, textView.isEditable, NSMaxRange(range) <= (textView.string as NSString).length,
              textView.shouldChangeText(in: range, replacementString: text) else { return false }
        textView.breakUndoCoalescing()
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        return true
    }

    func replaceAll(with text: String) -> Bool {
        guard let textView else { return false }
        let caret = textView.selectedRange().location
        guard replace(NSRange(location: 0, length: (textView.string as NSString).length), with: text) else { return false }
        textView.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
        return true
    }

    func perform(_ action: FormatAction) {
        apply { text, selection in
            switch action {
            case .wrap(let marker): MarkdownFormatting.toggleWrap(text, selection: selection, marker: marker)
            case .line(let prefix): MarkdownFormatting.toggleLinePrefix(text, selection: selection, prefix: prefix)
            case .link: MarkdownFormatting.insertLink(text, selection: selection)
            case .table(let rows, let columns): MarkdownFormatting.insertBlock(text, selection: selection, block: MarkdownFormatting.table(rows: rows, columns: columns), select: MarkdownFormatting.tableFirstCell)
            case .rule: MarkdownFormatting.insertBlock(text, selection: selection, block: MarkdownFormatting.rule)
            }
        }
    }

    /// Runs an edit through the text view, so it joins the undo history like typing.
    @discardableResult
    func apply(_ makeEdit: (String, NSRange) -> TextEdit?) -> Bool {
        guard let textView, textView.isEditable, let edit = makeEdit(textView.string, textView.selectedRange()),
              textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return false }
        textView.breakUndoCoalescing()
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        textView.window?.makeFirstResponder(textView)
        return true
    }

    func select(_ range: (String, NSRange) -> NSRange) {
        guard let textView else { return }
        let target = range(textView.string, textView.selectedRange())
        folds?.unfold(intersecting: target)
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
    }
}
