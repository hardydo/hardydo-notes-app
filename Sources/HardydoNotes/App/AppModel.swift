import AppKit
import HardydoNotesCore

@MainActor
final class AppModel {
    let store: NoteStore
    let preferences: Preferences
    let layout: LayoutSettings
    let dialogs: DialogModel
    let tabs: TabsModel
    let sidebar = SidebarModel()
    let groups: GroupsModel
    let workspace: WorkspaceEditor
    let find: FindModel
    let quickOpen: QuickOpenModel
    let globalSearch = GlobalSearchModel()
    private let exporter: NoteExporter
    private var inputMonitors: InputMonitors?

    /// Everything the first frame shows is loaded here, so the window opens with its notes and tabs already in place.
    init(store: NoteStore, groupsFile: JSONFile<NoteGroups>, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        let dialogs = DialogModel()
        self.dialogs = dialogs
        let layout = LayoutSettings(preferences: preferences)
        self.layout = layout
        let tabs = TabsModel(store: store, preferences: preferences)
        self.tabs = tabs
        groups = GroupsModel(store: store, file: groupsFile)
        let workspace = WorkspaceEditor(store: store, layout: layout, dialogs: dialogs) { tabs.selection }
        self.workspace = workspace
        find = FindModel(editor: workspace, store: store)
        quickOpen = QuickOpenModel(editor: workspace.controller)
        exporter = NoteExporter(preferences: preferences)
        tabs.leaving = { [weak self] in self?.leaveTab() }
        tabs.changed = { [weak self] in self?.tabsChanged($0) }
        tabs.restore()
        workspace.showLanguage()
    }

    func start() {
        guard inputMonitors == nil else { return }
        workspace.connectScrollSync()
        // Opened files are checked once the window is up, and again whenever the app comes back to the front.
        Task { await store.refreshLocalFiles() }
        inputMonitors = InputMonitors(
            zoom: { [weak self] in self?.layout.zoom(by: $0) },
            keyDown: { [weak self] in self?.cancelDrag(on: $0) == true || self?.handleSidebarShortcut($0) == true },
            middleClick: { [weak self] in self?.tabs.middleClick() == true || self?.middleClickNote() == true },
            activated: { [weak self] in
                guard let self else { return }
                Task { await self.store.refreshLocalFiles() }
            }
        )
    }

    /// Pending typing, notes, groups and tabs, all written before the app quits; returns what could not be saved.
    @discardableResult
    func flushAll() -> String? {
        workspace.controller.commit()
        let problem = store.saveNow()
        let groupsSaveProblem = groups.flush()
        let files = store.unsavedFileNames
        let filesProblem = files.isEmpty ? nil : "Edits to \(files.joined(separator: ", ")) haven’t reached the \(files.count == 1 ? "file" : "files") on disk. The text is still kept in the app."
        tabs.save()
        layout.flush()
        return [problem, groupsSaveProblem, filesProblem].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
    }

    private func leaveTab() {
        workspace.controller.commit()
        find.current = nil
        workspace.controller.pendingReveal = nil
    }

    private func tabsChanged(_ change: TabChange) {
        if change.old != change.new {
            sidebar.select(change.new)
            workspace.showLanguage()
        }
        workspace.controller.keepSessions(for: change.ids)
        workspace.keepLanguages(for: Set(change.ids))
    }

    var storageProblem: String? {
        store.fileError ?? groups.problem
    }

    func dismissStorageProblem() {
        store.dismissFileError()
        groups.dismissProblem()
    }

    func exportCurrent() {
        workspace.controller.commit()
        guard let note = workspace.note else { return }
        let language = workspace.language
        Task {
            do {
                try await exporter.export(note, language: language, from: NSApp.keyWindow)
            } catch {
                dialogs.showAlert("Couldn’t Export", error.localizedDescription)
            }
        }
    }

    /// A note kept in the app asks where to be saved as a file, like an untitled file in VS Code; an opened file is written in place.
    func save() {
        workspace.controller.commit()
        if let selection = tabs.selection { tabs.keep(selection) }
        store.saveNow()
        guard let note = workspace.note, note.localFile == nil else { return }
        let language = workspace.language
        Task {
            guard let url = await exporter.chooseFile(for: note, language: language, from: NSApp.keyWindow) else { return }
            workspace.controller.commit()
            do {
                try store.saveAsFile(note.id, to: url)
                notesRemoved()
            } catch {
                dialogs.showAlert("Couldn’t Save", error.localizedDescription)
            }
        }
    }

    func newNote() {
        workspace.leavePreview(to: .edit)
        tabs.open(store.createNote(), keep: true)
    }

    func newNote(inGroup group: NoteGroup.ID) {
        workspace.leavePreview(to: .edit)
        let id = store.createNote()
        groups.add(id, to: group)
        tabs.open(id, keep: true)
    }

    /// Takes an opened file off the list; the file itself stays on disk.
    func closeFile(_ id: Note.ID) {
        if id == tabs.selection { workspace.controller.commit() }
        store.close(id)
        notesRemoved()
    }

    /// The middle button on a sidebar row does what its ✕ does, as the middle button on a tab closes it.
    func middleClickNote() -> Bool {
        guard let id = sidebar.noteUnderPointer, store.note(id) != nil else { return false }
        sidebar.noteUnderPointer = nil
        requestDelete(id)
        return true
    }

    func requestDelete(_ id: Note.ID?) {
        guard let id, let note = store.note(id), !note.isLocked else { return }
        guard note.localFile == nil else {
            closeFile(id)
            return
        }
        dialogs.pendingDelete = id
    }

    func confirmDelete() {
        guard let id = dialogs.pendingDelete else { return }
        dialogs.pendingDelete = nil
        store.delete(id)
        notesRemoved()
    }

    func requestRename(_ id: Note.ID) {
        guard let note = store.note(id), note.localFile == nil, !note.isLocked else { return }
        dialogs.renameText = note.title
        dialogs.pendingRename = id
    }

    func confirmRename() {
        guard let id = dialogs.pendingRename else { return }
        dialogs.pendingRename = nil
        store.rename(id, to: dialogs.renameText)
    }

    func confirmClearEmptyNotes(_ chosen: Set<Note.ID>) {
        dialogs.isClearingEmptyNotes = false
        store.deleteEmptyNotes(chosen)
        notesRemoved()
    }

    private func notesRemoved() {
        tabs.prune()
        groups.prune()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
