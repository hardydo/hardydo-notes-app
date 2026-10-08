import HardydoNotesCore
import Foundation

extension AppModel {
    func loadGroups() {
        guard let saved = groupsFile.load() else { return }
        groups = saved
        pruneGroups()
    }

    func pruneGroups() {
        let existing = Set(store.notes.map(\.id))
        var pruned = groups
        pruned.prune(keeping: existing)
        guard pruned != groups else { return }
        changeGroups { $0 = pruned }
        if let editingGroup, groups.group(editingGroup) == nil { self.editingGroup = nil }
    }

    func changeGroups(_ change: (inout NoteGroups) -> Void) {
        var updated = groups
        change(&updated)
        guard updated != groups else { return }
        groups = updated
        groupsFile.save(groups)
    }

    func canGroup(_ note: Note.ID) -> Bool {
        store.note(note).map { $0.localFile == nil } ?? false
    }

    func addToNewGroup(_ note: Note.ID) {
        guard canGroup(note) else { return }
        var created: NoteGroup.ID?
        changeGroups { created = $0.create(name: "New Group", with: note) }
        // A popover asked for while its header is still being inserted never shows, so it opens once the header is on screen.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.editingGroup = created
        }
    }

    func add(_ note: Note.ID, toGroup group: NoteGroup.ID) {
        guard canGroup(note) else { return }
        placeAtEnd(of: group, note)
        changeGroups {
            $0.add(note, to: group)
            $0.update(group) { $0.isCollapsed = false }
        }
    }

    func removeFromGroup(_ note: Note.ID) {
        changeGroups { $0.remove(note) }
    }

    func ungroup(_ group: NoteGroup.ID) {
        if editingGroup == group { editingGroup = nil }
        changeGroups { $0.ungroup(group) }
    }

    func setPinned(_ note: Note.ID, _ pinned: Bool) {
        store.setPinned(note, pinned)
        if pinned { changeGroups { $0.pinIfAllPinned(groupOf: note, in: store.notes) } }
    }

    func setGroupPinned(_ group: NoteGroup.ID, _ pinned: Bool) {
        changeGroups { $0.update(group) { $0.isPinned = pinned } }
    }

    func toggleGroup(_ group: NoteGroup.ID) {
        changeGroups { $0.update(group) { $0.isCollapsed.toggle() } }
    }

    func renameGroup(_ group: NoteGroup.ID, _ name: String) {
        changeGroups { $0.update(group) { $0.name = name } }
    }

    func setGroupColor(_ group: NoteGroup.ID, _ color: GroupColor) {
        changeGroups { $0.update(group) { $0.color = color } }
    }

    func newNote(inGroup group: NoteGroup.ID) {
        if viewMode == .preview { viewMode = .edit }
        let id = store.createNote()
        add(id, toGroup: group)
        selectNote(id, keep: true)
    }

    // A group shows where its first note is, so a note joining it moves next to the others instead of dragging the group along.
    private func placeAtEnd(of group: NoteGroup.ID, _ note: Note.ID) {
        let others = store.notes.indices.filter { store.notes[$0].id != note && groups.group(of: store.notes[$0].id)?.id == group }
        guard let last = others.last, let from = store.notes.firstIndex(where: { $0.id == note }) else { return }
        store.move(fromOffsets: [from], toOffset: last + 1)
    }
}
