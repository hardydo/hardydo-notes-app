import HardydoNotesCore
import Foundation

extension AppModel {
    func loadGroups() {
        let loaded = groupsFile.load()
        groupsProblem = loaded.problem
        guard let saved = loaded.value else { return }
        groups = saved
        if persistsSidebarState { pruneGroups() }
    }

    func pruneGroups() {
        let existing = Set(store.notes.map(\.id))
        var pruned = groups
        pruned.prune(keeping: existing)
        guard pruned != groups else { return }
        changeGroups { $0 = pruned }
        if let editingGroup, groups.group(editingGroup) == nil { self.editingGroup = nil }
    }

    /// Changes show at once; `saveAfter` holds the save back, so typing a name writes the file once it pauses.
    func changeGroups(saveAfter delay: Duration? = nil, _ change: (inout NoteGroups) -> Void) {
        var updated = groups
        change(&updated)
        guard updated != groups else { return }
        groups = updated
        groupSaveTask?.cancel()
        guard let delay else { return saveGroupsNow() }
        groupSaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveGroupsNow()
        }
    }

    func saveGroupsNow() {
        groupSaveTask?.cancel()
        groupSaveTask = nil
        guard persistsSidebarState else { return }
        groupsFile.save(groups) { [weak self] error in
            self?.groupsProblem = "Couldn’t save your groups: \(error.localizedDescription)"
        }
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
        if let move = groups.insertionIndex(joining: group, for: note, in: store.notes) {
            store.move(fromOffsets: [move.from], toOffset: move.toOffset)
        }
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
        changeGroups(saveAfter: .milliseconds(300)) { $0.update(group) { $0.name = name } }
    }

    func setGroupColor(_ group: NoteGroup.ID, _ color: GroupColor) {
        changeGroups { $0.update(group) { $0.color = color } }
    }

    func newNote(inGroup group: NoteGroup.ID) {
        leavePreview(to: .edit)
        let id = store.createNote()
        add(id, toGroup: group)
        selectNote(id, keep: true)
    }
}
