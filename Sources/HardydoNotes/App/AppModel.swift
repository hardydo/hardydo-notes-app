import AppKit
import HardydoNotesCore
import Observation
import SwiftUI
import WebKit

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
    let defaults: UserDefaults
    var tabList = TabList()
    var viewMode = ViewMode.edit {
        // Leaving the editor tears it down inside a view update, which is no place to hand typing to the store.
        willSet { if newValue != viewMode { editor.commit() } }
    }
    var pendingDelete: Note.ID?
    var pendingRename: Note.ID?
    var renameText = ""
    var isClearingEmptyNotes = false
    var alert: AppAlert?
    var isInsertingTable = false
    private(set) var splitRatio = 0.5
    private(set) var zoom: CGFloat = 1
    var isScrollSynced = true
    var sidebarVisibility = NavigationSplitViewVisibility.all
    var groups = NoteGroups()
    var editingGroup: NoteGroup.ID?
    var quickOpen: QuickOpenMode?
    var showFind = false
    var showReplace = false
    var findQuery = ""
    var replaceText = ""
    var findOptions = SearchOptions()
    var findCurrent: NSRange?
    var findFocusRequest = 0
    var isSearchingAll = false
    var globalQuery = "" {
        didSet { if globalQuery != oldValue { collapsedResults = [] } }
    }
    var collapsedResults: Set<Note.ID> = []
    var searchFocusRequest = 0
    private var languageRevision = 0
    @ObservationIgnored let sidebarReorder = ReorderSession(axis: .vertical, space: "sidebar")
    @ObservationIgnored let fileReorder = ReorderSession(axis: .vertical, space: "sidebar")
    @ObservationIgnored let tabReorder = ReorderSession(axis: .horizontal, space: "tabs")
    @ObservationIgnored var tabUnderPointer: Note.ID?
    @ObservationIgnored var noteUnderPointer: Note.ID?
    @ObservationIgnored var findMemo: (key: FindKey, result: FindResult)?
    @ObservationIgnored var globalMemo: (key: GlobalKey, results: [GlobalResult])?
    @ObservationIgnored private var languageMemo: (key: LanguageKey, language: ContentLanguage)?
    @ObservationIgnored private var languageTask: Task<Void, Never>?
    @ObservationIgnored let groupsFile: JSONFile<NoteGroups>
    @ObservationIgnored private let exporter = NoteExporter()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var zoomSave: Task<Void, Never>?
    private static let zoomRange: ClosedRange<CGFloat> = 0.6...3
    private static let zoomKey = "zoom"
    private static let splitRatioKey = "splitRatio"
    static let scrollSyncKey = "scrollSync"

    /// Everything the first frame shows is loaded here, so the window opens with its notes and tabs already in place.
    init(store: NoteStore, groupsFile: JSONFile<NoteGroups>, defaults: UserDefaults = .standard) {
        self.store = store
        self.groupsFile = groupsFile
        self.defaults = defaults
        if defaults.double(forKey: Self.zoomKey) > 0 { zoom = CGFloat(defaults.double(forKey: Self.zoomKey)).clamped(to: Self.zoomRange) }
        if defaults.double(forKey: Self.splitRatioKey) > 0 { splitRatio = Self.clampedSplit(defaults.double(forKey: Self.splitRatioKey)) }
        if defaults.object(forKey: Self.scrollSyncKey) != nil { isScrollSynced = defaults.bool(forKey: Self.scrollSyncKey) }
        restoreTabs()
        loadGroups()
    }

    func start() {
        guard !started else { return }
        started = true
        connectScrollSync()
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refreshLocalFiles() }
        }
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleZoomGesture(event) ?? false }
                return handled ? nil : event
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleSidebarShortcut(event) ?? false }
                return handled ? nil : event
            },
            NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
                let handled = MainActor.assumeIsolated { event.buttonNumber == 2 && (self?.middleClickTab() == true || self?.middleClickNote() == true) }
                return handled ? nil : event
            },
        ].compactMap { $0 }
    }

    /// Pending typing, notes, groups and tabs, all written before the app quits; returns what could not be saved.
    @discardableResult
    func flushAll() -> String? {
        editor.commit()
        let problem = store.saveNow()
        let groupsProblem = groupsFile.flush().map { "Couldn’t save your groups: \($0.localizedDescription)" }
        saveTabs()
        if zoomSave != nil { defaults.set(Double(zoom), forKey: Self.zoomKey) }
        return [problem, groupsProblem].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
    }

    var selectedNote: Note? {
        selection.flatMap(store.note)
    }

    /*
     Detecting the content type reads the whole note, so it runs once when a note opens and, while typing,
     again in the background after a pause; the editor keeps the last answer until then.
     */
    var selectedLanguage: ContentLanguage {
        _ = languageRevision
        guard let note = selectedNote else { return .markdown }
        let key = LanguageKey(note: note.id, modifiedAt: note.modifiedAt, path: note.localFile?.path)
        if let languageMemo {
            if languageMemo.key == key { return languageMemo.language }
            if languageMemo.key.note == key.note, languageMemo.key.path == key.path {
                detectLanguageLater(note, key: key)
                return languageMemo.language
            }
        }
        let language = note.language
        languageMemo = (key, language)
        return language
    }

    private func detectLanguageLater(_ note: Note, key: LanguageKey) {
        languageTask?.cancel()
        languageTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let language = await Task.detached(priority: .utility) { note.language }.value
            guard !Task.isCancelled, let self else { return }
            let changed = self.languageMemo?.language != language
            self.languageMemo = (key, language)
            if changed { self.languageRevision += 1 }
        }
    }

    /// Notes kept in the app, then files opened from disk, in sidebar order.
    var visibleNotes: [Note] {
        groups.visibleNotes(store.appNotes) + store.localFileNotes
    }

    func moveSelection(by offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else { return }
        if let current = notes.firstIndex(where: { $0.id == selection }) {
            selectNote(notes[min(max(current + offset, 0), notes.count - 1)].id)
            return
        }
        // The open note may sit in a collapsed group: step from its place in the full list to the next note shown.
        let all = groups.orderedNotes(store.appNotes) + store.localFileNotes
        guard let position = all.firstIndex(where: { $0.id == selection }) else { return selectNote(notes[0].id) }
        let shown = Set(notes.map(\.id))
        let ahead = offset > 0 ? Array(all[(position + 1)...]) : all[..<position].reversed()
        selectNote((ahead.first { shown.contains($0.id) } ?? (offset > 0 ? notes[notes.count - 1] : notes[0])).id)
    }

    /// Shows a note in a tab: an open tab is reused, otherwise it opens in the preview tab unless `keep` is set.
    func selectNote(_ id: Note.ID, keep: Bool = false) {
        changeTabs { $0.open(id, keep: keep) }
    }

    func setZoom(_ value: CGFloat) {
        zoom = value.clamped(to: Self.zoomRange)
        zoomSave?.cancel()
        zoomSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.defaults.set(Double(self.zoom), forKey: Self.zoomKey)
            self.zoomSave = nil
        }
    }

    private func handleZoomGesture(_ event: NSEvent) -> Bool {
        guard event.type == .magnify || event.modifierFlags.contains(.command),
              let hit = event.window?.contentView?.hitTest(event.locationInWindow),
              sequence(first: hit, next: \.superview).contains(where: { $0 is NSTextView || $0 is WKWebView })
        else { return false }
        let factor = event.type == .magnify
            ? 1 + event.magnification
            : exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05))
        setZoom(zoom * factor)
        return true
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

    private static func clampedSplit(_ ratio: Double) -> Double {
        min(max(ratio, 0.15), 0.85)
    }

    func dragSplit(to ratio: Double) {
        splitRatio = Self.clampedSplit(ratio)
    }

    func endSplitDrag() {
        defaults.set(splitRatio, forKey: Self.splitRatioKey)
    }

    func exportCurrent() {
        editor.commit()
        guard let note = selectedNote else { return }
        store.saveNow()
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
        selectedNote?.isLocked == false && selectedLanguage == .json && viewMode != .preview
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
        if viewMode == .preview { viewMode = .edit }
        selectNote(store.createNote(), keep: true)
    }

    /// Takes an opened file off the list; the file itself stays on disk.
    func closeFile(_ id: Note.ID) {
        if id == selection { editor.commit() }
        store.close(id)
        notesRemoved()
    }

    /// The middle button on a sidebar row does what its ✕ does, as it closes a tab.
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

    /// Tabs and groups of notes that are gone go with them.
    private func notesRemoved() {
        pruneTabs()
        pruneGroups()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
