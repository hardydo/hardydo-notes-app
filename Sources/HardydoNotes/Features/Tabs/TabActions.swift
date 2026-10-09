import HardydoNotesCore

struct TabActions {
    let note: (Note.ID) -> NoteSummary?
    let setLocked: (Note.ID, Bool) -> Void
    let rename: (Note.ID) -> Void
    let newNote: () -> Void
}

extension AppModel {
    var tabActions: TabActions {
        TabActions(
            note: { [store] in store.note($0)?.summary },
            setLocked: { [workspace] in workspace.setLocked($0, $1) },
            rename: { [self] in requestRename($0) },
            newNote: { [self] in newNote() }
        )
    }
}
