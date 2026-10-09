import AppKit
import HardydoNotesCore
import Observation

enum ViewMode: Hashable {
    case edit
    case split
    case preview
}

struct LanguageKey: Equatable {
    let note: Note.ID
    let modifiedAt: Date
    let path: String?
}

@MainActor
@Observable
final class WorkspaceEditor {
    let controller = EditorController()
    var viewMode = ViewMode.edit {
        // Leaving the editor tears it down inside a view update, which is no place to hand typing to the store.
        willSet { if newValue != viewMode { controller.commit() } }
    }
    var isInsertingTable = false
    /// What the open note holds, as the editor colours it and the toolbar offers tools for it.
    private(set) var language = ContentLanguage.markdown
    /// One answer per open tab, so switching back and forth between tabs never detects again.
    @ObservationIgnored private var languages: [Note.ID: (key: LanguageKey, language: ContentLanguage)] = [:]
    @ObservationIgnored private(set) var preview: PreviewPage?
    private let store: NoteStore
    private let layout: LayoutSettings
    private let dialogs: DialogModel
    private let selection: () -> Note.ID?

    init(store: NoteStore, layout: LayoutSettings, dialogs: DialogModel, selection: @escaping () -> Note.ID?) {
        self.store = store
        self.layout = layout
        self.dialogs = dialogs
        self.selection = selection
    }

    var note: Note? {
        selection().flatMap(store.note)
    }

    var hasNote: Bool {
        selection() != nil
    }

    /*
     Detecting the content type reads the whole note, so it runs once when a note opens and, while typing,
     again in the background after a pause; the editor keeps the last answer until then.
     */
    var languageKey: LanguageKey? {
        note.map { LanguageKey(note: $0.id, modifiedAt: $0.modifiedAt, path: $0.localFile?.path) }
    }

    /// A note seen before shows its last answer; a new one is detected at once, so its first frame is already coloured.
    func showLanguage() {
        guard let note, let key = languageKey else { return setLanguage(.markdown) }
        if let known = languages[note.id], known.key.path == key.path { return setLanguage(known.language) }
        languages[note.id] = (key, note.language)
        setLanguage(note.language)
    }

    func refreshLanguage() async {
        guard let note, let key = languageKey, languages[note.id]?.key != key else { return }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        let language = await Task.detached(priority: .utility) { note.language }.value
        guard !Task.isCancelled, selection() == note.id else { return }
        languages[note.id] = (key, language)
        setLanguage(language)
    }

    private func setLanguage(_ language: ContentLanguage) {
        if self.language != language { self.language = language }
    }

    func keepLanguages(for notes: Set<Note.ID>) {
        languages = languages.filter { notes.contains($0.key) }
    }

    var canEditText: Bool {
        note?.isLocked == false && viewMode != .preview
    }

    var canFormatMarkdown: Bool {
        canEditText && language == .markdown
    }

    var canFormatDocument: Bool {
        canEditText && language == .json
    }

    /// Preview mode has no editor, so anything that edits or reveals text switches to a mode that shows one.
    func leavePreview(to mode: ViewMode) {
        if viewMode == .preview { viewMode = mode }
    }

    func togglePreview() {
        viewMode = viewMode == .preview ? .edit : .preview
    }

    func setLocked(_ id: Note.ID, _ locked: Bool) {
        if id == selection() { controller.commit() }
        store.setLocked(id, locked)
    }

    func toggleLock() {
        guard let note else { return }
        setLocked(note.id, !note.isLocked)
    }

    func moveLines(_ direction: LineEditing.Direction) {
        controller.apply { LineEditing.moveLines($0, selection: $1, direction) }
    }

    func copyLines(_ direction: LineEditing.Direction) {
        controller.apply { LineEditing.copyLines($0, selection: $1, direction) }
    }

    func deleteLines() {
        controller.apply { LineEditing.deleteLines($0, selection: $1) }
    }

    func insertLine(_ direction: LineEditing.Direction) {
        controller.apply { LineEditing.insertLine($0, selection: $1, direction) }
    }

    func indentLines() {
        controller.apply { LineEditing.indent($0, selection: $1, unit: LineEditing.indentUnit(for: $0)) }
    }

    func outdentLines() {
        controller.apply { LineEditing.outdent($0, selection: $1, unit: LineEditing.indentUnit(for: $0)) }
    }

    func toggleComment() {
        let language = language
        controller.apply { LineEditing.toggleComment($0, selection: $1, language: language) }
    }

    func selectLine() {
        controller.select { LineEditing.selectLine($0, selection: $1) }
    }

    var lineCount: Int {
        guard let note else { return 0 }
        return controller.lineCount ?? LineIndex(note.body as NSString).count
    }

    func goToLine(_ line: Int) {
        guard let note else { return }
        let target = NSRange(location: LineEditing.location(ofLine: line, in: note.body), length: 0)
        if controller.textView == nil {
            controller.pendingReveal = target
        } else {
            controller.select { _, _ in target }
            controller.focus()
        }
    }

    /// Pretty-prints a JSON note through the editor, so ⌘Z brings the old text back; Preview mode has no editor, so it is left out.
    func formatDocument() {
        controller.commit()
        guard canFormatDocument, let note else { return }
        do {
            let formatted = try JSONFormatter.format(note.body)
            guard formatted != note.body else { return }
            if !controller.replaceAll(with: formatted) {
                store.updateBody(note.id, formatted)
            }
        } catch {
            dialogs.showAlert("Couldn’t Format JSON", error.localizedDescription)
        }
    }

    /// In split view the preview keeps to the lines at the top of the editor, and the editor to the preview's.
    var isSyncingScroll: Bool {
        layout.isScrollSynced && viewMode == .split
    }

    func toggleScrollSync() {
        layout.toggleScrollSync()
        alignPreview()
    }

    func connectScrollSync() {
        controller.onScroll = { [weak self] in self?.alignPreview() }
    }

    /// The preview's page, made the first time a preview shows so a window that never previews never starts WebKit.
    func previewPage() -> PreviewPage {
        if let preview { return preview }
        let page = PreviewPage()
        page.onShow = { [weak self] in self?.alignPreview() }
        page.onScroll = { [weak self] line in
            guard let self, isSyncingScroll else { return }
            controller.scroll(toLine: line)
        }
        preview = page
        return page
    }

    private func alignPreview() {
        guard isSyncingScroll, let line = controller.topLine else { return }
        preview?.scroll(toLine: line)
    }
}
