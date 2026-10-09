import HardydoNotesCore

/// The sidebar's drag sessions and row selection. Nothing here is observed as a whole, so a row only follows its own state.
@MainActor
final class SidebarModel {
    let reorder = ReorderSession(axis: .vertical, space: "sidebar")
    let fileReorder = ReorderSession(axis: .vertical, space: "sidebar")
    var noteUnderPointer: Note.ID?
    private var rowStates: [Note.ID: RowState] = [:]
    private var selected: Note.ID?

    /// The selection a sidebar row draws. Asking for a row's state never makes a view depend on the others.
    func rowState(_ id: Note.ID) -> RowState {
        if let state = rowStates[id] { return state }
        let state = RowState(isSelected: selected == id)
        rowStates[id] = state
        return state
    }

    func select(_ id: Note.ID?) {
        guard id != selected else { return }
        if let selected { rowStates[selected]?.isSelected = false }
        if let id { rowStates[id]?.isSelected = true }
        selected = id
    }

    var isPressed: Bool {
        reorder.isPressed || fileReorder.isPressed
    }

    func cancelDrags() {
        reorder.cancel()
        fileReorder.cancel()
    }
}
