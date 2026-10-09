import Foundation
import HardydoNotesCore
import Observation

@MainActor
@Observable
final class GroupsModel {
    private(set) var list = NoteGroups()
    /// The group whose rename and colour popover is open.
    var editing: NoteGroup.ID?
    private(set) var problem: String?
    let store: NoteStore
    private let file: JSONFile<NoteGroups>
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(store: NoteStore, file: JSONFile<NoteGroups>) {
        self.store = store
        self.file = file
        load()
    }

    /// Groups refer to notes by id, so they are only pruned and saved against a notes list that loaded whole.
    private var persists: Bool {
        store.loadedCleanly
    }

    private func load() {
        let loaded = file.load()
        problem = loaded.problem
        guard let saved = loaded.value else { return }
        list = saved
        if persists { prune() }
    }

    func dismissProblem() {
        problem = nil
    }

    func prune() {
        // Opened files cannot be grouped, so a note saved as a file leaves its group too.
        let existing = Set(store.notes.lazy.filter { $0.localFile == nil }.map(\.id))
        var pruned = list
        pruned.prune(keeping: existing)
        guard pruned != list else { return }
        change { $0 = pruned }
        if let editing, list.group(editing) == nil { self.editing = nil }
    }

    /// Changes show at once; `saveAfter` holds the save back, so typing a name writes the file once it pauses.
    func change(saveAfter delay: Duration? = nil, _ change: (inout NoteGroups) -> Void) {
        var updated = list
        change(&updated)
        guard updated != list else { return }
        list = updated
        saveTask?.cancel()
        guard let delay else { return saveNow() }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard persists else { return }
        file.save(list) { [weak self] error in
            self?.problem = "Couldn’t save your groups: \(error.localizedDescription)"
        }
    }

    /// Writes what is pending before the app quits; returns why it could not.
    func flush() -> String? {
        saveNow()
        return file.flush().map { "Couldn’t save your groups: \($0.localizedDescription)" }
    }

    func canGroup(_ note: Note.ID) -> Bool {
        store.note(note).map { $0.localFile == nil } ?? false
    }

    func addToNewGroup(_ note: Note.ID) {
        guard canGroup(note) else { return }
        var created: NoteGroup.ID?
        change { created = $0.create(name: "New Group", with: note) }
        // A popover asked for while its header is still being inserted never shows, so it opens once the header is on screen.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.editing = created
        }
    }

    func add(_ note: Note.ID, to group: NoteGroup.ID) {
        guard canGroup(note) else { return }
        if let move = list.insertionIndex(joining: group, for: note, in: store.notes) {
            store.move(fromOffsets: [move.from], toOffset: move.toOffset)
        }
        change {
            $0.add(note, to: group)
            $0.update(group) { $0.isCollapsed = false }
        }
    }

    func remove(_ note: Note.ID) {
        change { $0.remove(note) }
    }

    func ungroup(_ group: NoteGroup.ID) {
        if editing == group { editing = nil }
        change { $0.ungroup(group) }
    }

    func setNotePinned(_ note: Note.ID, _ pinned: Bool) {
        store.setPinned(note, pinned)
        if pinned { change { $0.pinIfAllPinned(groupOf: note, in: store.notes) } }
    }

    func setPinned(_ group: NoteGroup.ID, _ pinned: Bool) {
        change { $0.update(group) { $0.isPinned = pinned } }
    }

    func toggle(_ group: NoteGroup.ID) {
        change { $0.update(group) { $0.isCollapsed.toggle() } }
    }

    func rename(_ group: NoteGroup.ID, to name: String) {
        change(saveAfter: .milliseconds(300)) { $0.update(group) { $0.name = name } }
    }

    func setColor(_ group: NoteGroup.ID, _ color: GroupColor) {
        change { $0.update(group) { $0.color = color } }
    }
}
