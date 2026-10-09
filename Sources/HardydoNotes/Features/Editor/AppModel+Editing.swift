import AppKit
import HardydoNotesCore

extension AppModel {
    var canEditText: Bool {
        selectedNote?.isLocked == false && viewMode != .preview
    }

    var canFormatMarkdown: Bool {
        canEditText && selectedLanguage == .markdown
    }

    /// Preview mode has no editor, so anything that edits or reveals text switches to a mode that shows one.
    func leavePreview(to mode: ViewMode) {
        if viewMode == .preview { viewMode = mode }
    }

    func moveLines(_ direction: LineEditing.Direction) {
        editor.apply { LineEditing.moveLines($0, selection: $1, direction) }
    }

    func copyLines(_ direction: LineEditing.Direction) {
        editor.apply { LineEditing.copyLines($0, selection: $1, direction) }
    }

    func deleteLines() {
        editor.apply { LineEditing.deleteLines($0, selection: $1) }
    }

    func insertLine(_ direction: LineEditing.Direction) {
        editor.apply { LineEditing.insertLine($0, selection: $1, direction) }
    }

    func indentLines() {
        editor.apply { LineEditing.indent($0, selection: $1, unit: LineEditing.indentUnit(for: $0)) }
    }

    func outdentLines() {
        editor.apply { LineEditing.outdent($0, selection: $1, unit: LineEditing.indentUnit(for: $0)) }
    }

    func toggleComment() {
        let language = selectedLanguage
        editor.apply { LineEditing.toggleComment($0, selection: $1, language: language) }
    }

    func selectLine() {
        editor.select { LineEditing.selectLine($0, selection: $1) }
    }

    func goToLine(_ line: Int) {
        guard let note = selectedNote else { return }
        let target = NSRange(location: LineEditing.location(ofLine: line, in: note.body), length: 0)
        if editor.textView == nil {
            editor.pendingReveal = target
        } else {
            editor.select { _, _ in target }
            editor.focus()
        }
    }

    func setLocked(_ id: Note.ID, _ locked: Bool) {
        if id == selection { editor.commit() }
        store.setLocked(id, locked)
    }
}
