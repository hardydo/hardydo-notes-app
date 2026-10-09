import AppKit
import HardydoNotesCore

final class CodeTextView: NSTextView {
    let folds = FoldState()
    /// Kept current by the editor's storage delegate; the gutter, folds and scroll sync all read it.
    private(set) var lines = LineIndex("")
    var onFocusChange: (Bool) -> Void = { _ in }
    var onCaretMove: (Int) -> Void = { _ in }
    private let caret = SmoothCaret()
    private var windowObservers: [NSObjectProtocol] = []
    private var isCaretRefreshPending = false

    isolated deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func reindexLines() {
        lines = LineIndex(string as NSString)
    }

    /// Updates the line starts for an edit and returns the old lines it touched and how many lines it added.
    func updateLines(edited: NSRange, delta: Int) -> (first: Int, last: Int, added: Int) {
        let first = lines.line(at: edited.location)
        let last = lines.line(at: NSMaxRange(edited) - delta)
        return (first, last, lines.update(string as NSString, edited: edited, delta: delta))
    }

    var caretLine: Int {
        lines.line(at: selectedRange().location)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange(true) }
        refreshCaret(animated: false)
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange(false) }
        refreshCaret(animated: false)
        return resigned
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { onCaretMove(selectedRange().location) }
        refreshCaret(animated: true)
    }

    override var shouldDrawInsertionPoint: Bool { false }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if caret.superview !== self { addSubview(caret) }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        guard let window else { return }
        windowObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshCaret(animated: false) }
            }
        }
        refreshCaret(animated: false)
    }

    // Typing, folding, zooming and rewrapping all redraw the text; the caret follows once layout has settled.
    private func scheduleCaretRefresh() {
        guard !isCaretRefreshPending else { return }
        isCaretRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.isCaretRefreshPending = false
            self?.refreshCaret(animated: false)
        }
    }

    private func refreshCaret(animated: Bool) {
        caret.move(to: caretRect, animated: animated)
    }

    private var caretRect: NSRect? {
        let selection = selectedRange()
        guard selection.length == 0, let window, window.isKeyWindow, window.firstResponder === self else { return nil }
        let line = convert(window.convertFromScreen(firstRect(forCharacterRange: selection, actualRange: nil)), from: nil)
        guard line.height > 0 else { return nil }
        return NSRect(x: line.minX.rounded(), y: line.minY, width: 2, height: line.height)
    }

    // The inset keeps a margin on the right only; the text starts right after the gutter.
    override var textContainerOrigin: NSPoint {
        NSPoint(x: 0, y: super.textContainerOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        folds.drawBadges(in: dirtyRect)
        scheduleCaretRefresh()
    }

    override func mouseDown(with event: NSEvent) {
        if let fold = folds.fold(atBadge: convert(event.locationInWindow, from: nil)) {
            folds.unfold(fold)
            setSelectedRange(NSRange(location: fold.location, length: 0))
            return
        }
        super.mouseDown(with: event)
    }

    // A read-only NSTextView scrolls on ↑ and ↓; a locked note still moves its caret, as in VS Code.
    override func moveUp(_ sender: Any?) { whileEditable { super.moveUp(sender) } }
    override func moveDown(_ sender: Any?) { whileEditable { super.moveDown(sender) } }
    override func moveToBeginningOfDocument(_ sender: Any?) { whileEditable { super.moveToBeginningOfDocument(sender) } }
    override func moveToEndOfDocument(_ sender: Any?) { whileEditable { super.moveToEndOfDocument(sender) } }

    private func whileEditable(_ move: () -> Void) {
        guard !isEditable else { return move() }
        isEditable = true
        defer { isEditable = false }
        move()
    }

    // Like VS Code, copy and cut with nothing selected take the whole line.
    override func copy(_ sender: Any?) {
        guard selectedRange().length == 0 else { return super.copy(sender) }
        copyLine()
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length == 0, isEditable else { return super.cut(sender) }
        copyLine()
        let edit = LineEditing.deleteLines(string, selection: selectedRange())
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }

    private func copyLine() {
        let text = string as NSString
        var line = text.substring(with: LineEditing.lineBlock(text, selectedRange()))
        if !line.hasSuffix("\n") { line += "\n" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }
}
