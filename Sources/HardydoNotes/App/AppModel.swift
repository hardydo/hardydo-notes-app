import AppKit
import HardydoNotesCore
import Observation
import SwiftUI

enum ViewMode: Hashable {
    case edit
    case split
    case preview
}

struct AppAlert {
    let title: String
    let message: String
}

struct LanguageKey: Equatable {
    let note: Note.ID
    let modifiedAt: Date
    let path: String?
}

@MainActor
@Observable
final class AppModel {
    let store: NoteStore
    let editor = EditorController()
    let preferences: Preferences
    let layout: LayoutSettings
    var tabList = TabList() {
        didSet {
            guard oldValue.active != tabList.active else { return }
            if let old = oldValue.active { rowStates[old]?.isSelected = false }
            if let new = tabList.active { rowStates[new]?.isSelected = true }
            showLanguage()
        }
    }
    var viewMode = ViewMode.edit {
        // Leaving the editor tears it down inside a view update, which is no place to hand typing to the store.
        willSet { if newValue != viewMode { editor.commit() } }
    }
    var pendingDelete: Note.ID?
    var pendingRename: Note.ID?
    var renameText = ""
    var isClearingEmptyNotes = false
    var alert: AppAlert?
    var groupsProblem: String?
    var isInsertingTable = false
    @ObservationIgnored var preview: PreviewPage?
    var groups = NoteGroups()
    var editingGroup: NoteGroup.ID?
    var quickOpen: QuickOpenMode?
    let find = FindModel()
    let globalSearch = GlobalSearchModel()
    /// Shared by find and the search of every note.
    var searchOptions = SearchOptions()
    /// What the open note holds, as the editor colours it and the toolbar offers tools for it.
    private(set) var selectedLanguage = ContentLanguage.markdown
    @ObservationIgnored let sidebarReorder = ReorderSession(axis: .vertical, space: "sidebar")
    @ObservationIgnored let fileReorder = ReorderSession(axis: .vertical, space: "sidebar")
    @ObservationIgnored let tabReorder = ReorderSession(axis: .horizontal, space: "tabs")
    @ObservationIgnored var tabUnderPointer: Note.ID?
    @ObservationIgnored var noteUnderPointer: Note.ID?
    /// One answer per open tab, so switching back and forth between tabs never detects again.
    @ObservationIgnored private var languages: [Note.ID: (key: LanguageKey, language: ContentLanguage)] = [:]
    @ObservationIgnored let groupsFile: JSONFile<NoteGroups>
    @ObservationIgnored private var rowStates: [Note.ID: RowState] = [:]
    @ObservationIgnored var tabSaveTask: Task<Void, Never>?
    @ObservationIgnored var groupSaveTask: Task<Void, Never>?
    @ObservationIgnored private let exporter: NoteExporter
    @ObservationIgnored private var inputMonitors: InputMonitors?

    /// Everything the first frame shows is loaded here, so the window opens with its notes and tabs already in place.
    init(store: NoteStore, groupsFile: JSONFile<NoteGroups>, preferences: Preferences) {
        self.store = store
        self.groupsFile = groupsFile
        self.preferences = preferences
        layout = LayoutSettings(preferences: preferences)
        exporter = NoteExporter(preferences: preferences)
        restoreTabs()
        showLanguage()
        loadGroups()
    }

    func start() {
        guard inputMonitors == nil else { return }
        connectScrollSync()
        // Opened files are checked once the window is up, and again whenever the app comes back to the front.
        Task { await store.refreshLocalFiles() }
        inputMonitors = InputMonitors(
            zoom: { [weak self] in self?.layout.zoom(by: $0) },
            keyDown: { [weak self] in self?.cancelDrag(on: $0) == true || self?.handleSidebarShortcut($0) == true },
            middleClick: { [weak self] in self?.middleClickTab() == true || self?.middleClickNote() == true },
            activated: { [weak self] in
                guard let self else { return }
                Task { await self.store.refreshLocalFiles() }
            }
        )
    }

    /// Pending typing, notes, groups and tabs, all written before the app quits; returns what could not be saved.
    @discardableResult
    func flushAll() -> String? {
        editor.commit()
        let problem = store.saveNow()
        saveGroupsNow()
        let groupsSaveProblem = groupsFile.flush().map { "Couldn’t save your groups: \($0.localizedDescription)" }
        let files = store.unsavedFileNames
        let filesProblem = files.isEmpty ? nil : "Edits to \(files.joined(separator: ", ")) haven’t reached the \(files.count == 1 ? "file" : "files") on disk. The text is still kept in the app."
        saveTabs()
        layout.flush()
        return [problem, groupsSaveProblem, filesProblem].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
    }

    /// The selection a sidebar row draws. The registry is not observed, so asking for a row's state never makes a view depend on the others.
    func rowState(_ id: Note.ID) -> RowState {
        if let state = rowStates[id] { return state }
        let state = RowState(isSelected: tabList.active == id)
        rowStates[id] = state
        return state
    }

    /// Groups and tabs refer to notes by id, so they are only pruned and saved against a notes list that loaded whole.
    var persistsSidebarState: Bool {
        store.loadedCleanly
    }

    var storageProblem: String? {
        store.fileError ?? groupsProblem
    }

    func dismissStorageProblem() {
        store.dismissFileError()
        groupsProblem = nil
    }

    var selectedNote: Note? {
        selection.flatMap(store.note)
    }

    /*
     Detecting the content type reads the whole note, so it runs once when a note opens and, while typing,
     again in the background after a pause; the editor keeps the last answer until then.
     */
    var selectedLanguageKey: LanguageKey? {
        selectedNote.map { LanguageKey(note: $0.id, modifiedAt: $0.modifiedAt, path: $0.localFile?.path) }
    }

    /// A note seen before shows its last answer; a new one is detected at once, so its first frame is already coloured.
    func showLanguage() {
        guard let note = selectedNote, let key = selectedLanguageKey else { return setLanguage(.markdown) }
        if let known = languages[note.id], known.key.path == key.path { return setLanguage(known.language) }
        languages[note.id] = (key, note.language)
        setLanguage(note.language)
    }

    func refreshLanguage() async {
        guard let note = selectedNote, let key = selectedLanguageKey, languages[note.id]?.key != key else { return }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        let language = await Task.detached(priority: .utility) { note.language }.value
        guard !Task.isCancelled, selection == note.id else { return }
        languages[note.id] = (key, language)
        setLanguage(language)
    }

    private func setLanguage(_ language: ContentLanguage) {
        if selectedLanguage != language { selectedLanguage = language }
    }

    func keepLanguages(for notes: Set<Note.ID>) {
        languages = languages.filter { notes.contains($0.key) }
    }

    var visibleNotes: [Note] {
        groups.visibleNotes(store.appNotes) + store.localFileNotes
    }

    func moveSelection(by offset: Int) {
        guard let id = groups.step(from: selection, by: offset, appNotes: store.appNotes, fileNotes: store.localFileNotes) else { return }
        selectNote(id)
    }

    /// Shows a note in a tab: an open tab is reused, otherwise it opens in the transient tab unless `keep` is set.
    func selectNote(_ id: Note.ID, keep: Bool = false) {
        changeTabs { $0.open(id, keep: keep) }
    }

    func open(_ urls: [URL], at position: Int = 0) {
        var failures: [String] = []
        for (offset, url) in urls.enumerated() where url.isFileURL {
            do {
                selectNote(try store.openFile(url, at: position + offset), keep: true)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if !failures.isEmpty {
            alert = AppAlert(title: "Couldn’t Open File", message: failures.joined(separator: "\n"))
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .sourceCode, .json, .xml, .html, .yaml]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func exportCurrent() {
        editor.commit()
        guard let note = selectedNote else { return }
        let language = selectedLanguage
        Task {
            do {
                try await exporter.export(note, language: language, from: NSApp.keyWindow)
            } catch {
                alert = AppAlert(title: "Couldn’t Export", message: error.localizedDescription)
            }
        }
    }

    var canFormatDocument: Bool {
        canEditText && selectedLanguage == .json
    }

    /// Pretty-prints a JSON note through the editor, so ⌘Z brings the old text back; Preview mode has no editor, so it is left out.
    func formatDocument() {
        editor.commit()
        guard canFormatDocument, let note = selectedNote else { return }
        do {
            let formatted = try JSONFormatter.format(note.body)
            guard formatted != note.body else { return }
            if !editor.replaceAll(with: formatted) {
                store.updateBody(note.id, formatted)
            }
        } catch {
            alert = AppAlert(title: "Couldn’t Format JSON", message: error.localizedDescription)
        }
    }

    func togglePreview() {
        viewMode = viewMode == .preview ? .edit : .preview
    }

    func toggleLock() {
        guard let note = selectedNote else { return }
        setLocked(note.id, !note.isLocked)
    }

    func newNote() {
        leavePreview(to: .edit)
        selectNote(store.createNote(), keep: true)
    }

    /// Takes an opened file off the list; the file itself stays on disk.
    func closeFile(_ id: Note.ID) {
        if id == selection { editor.commit() }
        store.close(id)
        notesRemoved()
    }

    /// The middle button on a sidebar row does what its ✕ does, as the middle button on a tab closes it.
    func middleClickNote() -> Bool {
        guard let id = noteUnderPointer, store.note(id) != nil else { return false }
        noteUnderPointer = nil
        requestDelete(id)
        return true
    }

    func requestDelete(_ id: Note.ID?) {
        guard let id, let note = store.note(id), !note.isLocked else { return }
        guard note.localFile == nil else {
            closeFile(id)
            return
        }
        pendingDelete = id
    }

    func confirmDelete() {
        guard let id = pendingDelete else { return }
        pendingDelete = nil
        store.delete(id)
        notesRemoved()
    }

    func requestRename(_ id: Note.ID) {
        guard let note = store.note(id), note.localFile == nil, !note.isLocked else { return }
        renameText = note.title
        pendingRename = id
    }

    func confirmRename() {
        guard let id = pendingRename else { return }
        pendingRename = nil
        store.rename(id, to: renameText)
    }

    func confirmClearEmptyNotes() {
        isClearingEmptyNotes = false
        store.deleteEmptyNotes()
        notesRemoved()
    }

    private func notesRemoved() {
        pruneTabs()
        pruneGroups()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
