import Foundation
import HardydoNotesCore
import Testing

@MainActor
private struct FileFixture {
    let cache = temporaryNotesFile()
    let folder: URL

    init() {
        folder = cache.url.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func discard() {
        cache.discard()
    }

    func write(_ text: String, to name: String) -> URL {
        let url = folder.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}

@MainActor
private func legacyStore(in cache: NotesFile) -> NoteStore {
    let older = Note(body: "# Older", modifiedAt: Date(timeIntervalSince1970: 1_000))
    let newer = Note(body: "# Newer", modifiedAt: Date(timeIntervalSince1970: 2_000))
    let legacy = ##"{"notes":[\##(String(decoding: try! JSONEncoder().encode(older), as: UTF8.self)),\##(String(decoding: try! JSONEncoder().encode(newer), as: UTF8.self))]}"##
    try? Data(legacy.utf8).write(to: cache.url)
    return NoteStore(notesFile: cache)
}

@Suite struct NoteStoreTests {
    @Test func filesInTheTrashAreDetected() {
        #expect(NoteStore.isInTrash("/Users/me/.Trash/note.md"), "a file in the user Trash is in the Trash")
        #expect(NoteStore.isInTrash("/Volumes/Disk/.Trashes/501/note.md"), "a file in a volume Trash is in the Trash")
    }

    @Test func pathsOnlyNamedLikeTheTrashAreNotInIt() {
        #expect(!NoteStore.isInTrash("/Users/me/Notes/.Trash-notes/note.md"), "a folder only named like the Trash is not")
        #expect(!NoteStore.isInTrash("/Users/me/Notes/note.md"), "a regular file is not in the Trash")
    }

    @Test @MainActor func editsAreSavedShortlyAfterTyping() async {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "# Groceries\nmilk")
        store.updateBody(id, "# Groceries\nmilk\nbread")
        try? await Task.sleep(for: .milliseconds(600))
        #expect(NoteStore(notesFile: cache).note(id)?.body == "# Groceries\nmilk\nbread", "edits are saved shortly after typing")
    }

    @Test @MainActor func saveNowWritesEveryNote() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "# Groceries\nmilk\nbread")
        let other = store.createNote()
        store.updateBody(other, "# Other")
        store.saveNow()
        #expect(NoteStore(notesFile: cache).notes.map(\.title) == ["Other", "Groceries"], "save now writes every note")
    }

    @Test @MainActor func deletingIsSavedAndClosingOnlyAppliesToOpenedFiles() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "# Groceries\nmilk\nbread")
        let other = store.createNote()
        store.updateBody(other, "# Other")
        store.saveNow()

        store.delete(id)
        #expect(store.note(id) == nil, "delete removes the note")
        #expect(NoteStore(notesFile: cache).notes.map(\.id) == [other], "deleting is saved")
        store.close(other)
        #expect(store.note(other) != nil, "closing applies only to opened files")
    }

    @Test @MainActor func lockedNoteCannotBeEditedOrDeletedAndTheLockIsSaved() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "# Locked\noriginal")
        store.setLocked(id, true)
        store.updateBody(id, "# Locked\nchanged")
        #expect(store.note(id)?.body == "# Locked\noriginal", "locked note cannot be edited")
        store.delete(id)
        #expect(store.note(id) != nil, "locked note cannot be deleted")
        #expect(NoteStore(notesFile: cache).note(id)?.isLocked == true, "lock is saved locally")
    }

    @Test @MainActor func unlockedNoteCanBeEdited() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "# Locked\noriginal")
        store.setLocked(id, true)
        store.setLocked(id, false)
        store.updateBody(id, "# Locked\nchanged")
        #expect(store.note(id)?.body == "# Locked\nchanged", "unlocked note can be edited")
    }

    @Test @MainActor func oldCacheKeepsNewestFirstOrder() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = legacyStore(in: cache)
        #expect(store.notes.map(\.title) == ["Newer", "Older"], "old cache keeps newest-first order")
    }

    @Test @MainActor func draggingNotesMovesThemAndTheOrderIsSaved() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = legacyStore(in: cache)
        let fresh = store.createNote()
        #expect(store.notes.first?.id == fresh, "new note goes to the top")
        store.move(fromOffsets: [0], toOffset: 3)
        #expect(store.notes.map(\.title) == ["Newer", "Older", NoteNaming.untitled], "dragging a note moves it")
        store.move(fromOffsets: [1], toOffset: 0)
        #expect(store.notes.map(\.title) == ["Older", "Newer", NoteNaming.untitled], "dragging up moves it up")
        store.saveNow()
        #expect(NoteStore(notesFile: cache).notes.map(\.title) == ["Older", "Newer", NoteNaming.untitled], "custom order is saved")
    }

    @Test @MainActor func notesAreFoundByIDAfterTheListChanges() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let ids = (0..<4).map { index -> Note.ID in
            let id = store.createNote()
            store.updateBody(id, "# Note \(index)")
            return id
        }
        #expect(store.note(ids[0])?.title == "Note 0")
        store.reorder(ids)
        #expect(ids.allSatisfy { store.index(of: $0).map { store.notes[$0].id } == $0 }, "found after a reorder")
        store.delete(ids[1])
        #expect(store.note(ids[1]) == nil && store.note(ids[2])?.title == "Note 2", "found after a delete")
        let fresh = store.createNote()
        #expect(store.index(of: fresh) == 0 && store.note(ids[3])?.title == "Note 3", "found after a note is added")
        #expect(store.note(UUID()) == nil, "an unknown id is not found")
    }

    @Test @MainActor func openedTextFileIsListedApartFromAppNotes() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let url = fixture.write("buy milk\ncall mom", to: "todo.txt")
        let opened = try? store.openFile(url)
        #expect(opened.flatMap(store.note)?.body == "buy milk\ncall mom", "opening a text file shows its content")
        #expect(opened.flatMap(store.note)?.title == "todo.txt", "file note is titled by file name")
        #expect(store.notes.first?.id == opened, "opened file goes to the top")
        #expect((try? store.openFile(url)) == opened, "opening the same file again reuses its note")
        #expect(store.localFileNotes.map(\.id) == [opened!], "opened files are listed apart")
        #expect(!store.appNotes.contains { $0.id == opened }, "opened files are not app notes")
    }

    @Test @MainActor func editsAreWrittenToTheOpenedFile() async throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let url = fixture.write("buy milk\ncall mom", to: "todo.txt")
        let opened = try store.openFile(url)
        store.updateBody(opened, "buy milk\ncall mom\npay rent")
        store.saveNow()
        #expect(fixture.read(url) == "buy milk\ncall mom\npay rent", "edits are written to the file")
        store.updateBody(opened, "buy milk\ncall mom\npay rent\nwater plants")
        try? await Task.sleep(for: .milliseconds(800))
        #expect(fixture.read(url) == "buy milk\ncall mom\npay rent\nwater plants", "edits reach the file shortly after typing, written off the main thread")
        #expect(store.note(opened)?.localFile?.needsSave == false, "a finished background write clears the pending flag")
    }

    @Test @MainActor func changesMadeOutsideTheAppAreLoaded() async throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let url = fixture.write("buy milk\ncall mom\npay rent", to: "todo.txt")
        let opened = try store.openFile(url)
        store.saveNow()

        try? "changed elsewhere".write(to: url, atomically: true, encoding: .utf8)
        _ = try? store.openFile(url)
        #expect(store.note(opened)?.body == "changed elsewhere", "reopening picks up changes made outside the app")
        try? "changed while closed".write(to: url, atomically: true, encoding: .utf8)
        let relaunched = NoteStore(notesFile: fixture.cache)
        #expect(relaunched.note(opened)?.body == "changed elsewhere", "launch shows the saved text before checking files")
        await relaunched.refreshLocalFiles()
        #expect(relaunched.note(opened)?.body == "changed while closed", "file content is reloaded after launch")
    }

    @Test @MainActor func closingAFileNoteWritesPendingEditsAndKeepsTheFile() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let url = fixture.write("buy milk\ncall mom", to: "todo.txt")
        let opened = try store.openFile(url)
        store.delete(opened)
        #expect(store.note(opened) != nil, "delete does not remove a file note")
        store.updateBody(opened, "last edit")
        store.close(opened)
        #expect(store.note(opened) == nil, "closing takes the file off the list")
        #expect(fixture.read(url) == "last edit", "closing writes pending edits and keeps the file")
    }

    @Test @MainActor func foldersAreNotOpenedAsNotes() {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        #expect((try? store.openFile(fixture.folder)) == nil, "folders are not opened as notes")
    }

    @Test @MainActor func fileChangedByAnotherAppIsAConflictAndKeepingTheAppVersionWritesIt() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        var shared = fixture.write("v1", to: "shared.md")
        let original = Date(timeIntervalSince1970: 946_684_800)
        var values = URLResourceValues()
        values.creationDate = original
        try? shared.setResourceValues(values)
        let id = try store.openFile(shared)
        store.updateBody(id, "app edit")
        try? "other app".write(to: shared, atomically: true, encoding: .utf8)
        try? shared.setResourceValues(values)
        store.saveNow()
        #expect(store.fileConflict?.id == id, "a file changed by another app is reported as a conflict")
        #expect(fixture.read(shared) == "other app", "the other app's version is not overwritten")
        #expect(store.note(id)?.localFile?.needsSave == true, "unsaved edits are kept during a conflict")
        store.resolveFileConflict(keepAppVersion: true)
        store.saveNow()
        #expect(fixture.read(shared) == "app edit", "keeping the app version writes it")
        shared.removeAllCachedResourceValues()
        #expect((try? shared.resourceValues(forKeys: [.creationDateKey]))?.creationDate == original, "saving keeps the file's creation date")
    }

    @Test @MainActor func usingTheDiskVersionReplacesTheAppText() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let shared = fixture.write("v1", to: "shared.md")
        let id = try store.openFile(shared)
        store.updateBody(id, "second edit")
        try? "disk wins".write(to: shared, atomically: true, encoding: .utf8)
        store.saveNow()
        store.resolveFileConflict(keepAppVersion: false)
        #expect(store.note(id)?.body == "disk wins", "using the disk version replaces the app text")
        #expect(store.note(id)?.localFile?.needsSave == false, "using the disk version clears pending edits")
    }

    @Test @MainActor func outsideChangesLoadWhenTheAppBecomesActive() async throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let shared = fixture.write("v1", to: "shared.md")
        let id = try store.openFile(shared)
        let beforeRefresh = store.revision(of: id)
        try? "refreshed".write(to: shared, atomically: true, encoding: .utf8)
        await store.refreshLocalFiles()
        #expect(store.note(id)?.body == "refreshed", "outside changes load when the app becomes active")
        #expect(store.revision(of: id) > beforeRefresh, "text loaded from disk moves the revision, so the editor shows it")
    }

    @available(macOS 26, *)
    @Test @MainActor func aCheckThatBeganBeforeAnEditLeavesTheEditAlone() async throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let shared = fixture.write("v1", to: "shared.md")
        let id = try store.openFile(shared)
        try? "disk again".write(to: shared, atomically: true, encoding: .utf8)
        // Started immediately, the check lists the file before the edit and can only finish after it, however busy the machine is.
        let racing = Task.immediate { await store.refreshLocalFiles() }
        store.updateBody(id, "typed meanwhile")
        await racing.value
        #expect(store.note(id)?.body == "typed meanwhile", "a check that began before an edit leaves the edit alone")
        await store.refreshLocalFiles()
        #expect(store.fileConflict?.id == id, "the next check reports the outside change as a conflict with the unsaved edit")
        store.resolveFileConflict(keepAppVersion: true)
        store.saveNow()
        #expect(fixture.read(shared) == "typed meanwhile", "keeping the app version after a check writes it")
    }

    @Test @MainActor func missingFileReportsASaveErrorAndKeepsTheEdits() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let missing = fixture.write("x", to: "gone.txt")
        let gone = try store.openFile(missing)
        try? FileManager.default.removeItem(at: missing)
        store.updateBody(gone, "unsaved")
        store.saveNow()
        #expect(store.fileError != nil, "a missing file reports a save error")
        #expect(store.note(gone)?.localFile?.needsSave == true, "edits to a missing file are kept")
        store.dismissFileError()
        store.close(gone)
        #expect(store.note(gone) != nil && store.fileError != nil, "a note with unsaved file edits is not closed")
        store.dismissFileError()
    }

    @Test @MainActor func utf16FilesAreReadAndSavedInTheirEncoding() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let utf16 = fixture.folder.appendingPathComponent("utf16.txt")
        try? "Café déjà vu".write(to: utf16, atomically: true, encoding: .utf16)
        let wide = try store.openFile(utf16)
        #expect(store.note(wide)?.body == "Café déjà vu", "UTF-16 files are read")
        store.updateBody(wide, "Naïve résumé")
        store.saveNow()
        #expect((try? String(contentsOf: utf16, encoding: .utf16)) == "Naïve résumé", "files are saved in their original encoding")
    }

    @Test @MainActor func veryLargeFilesAreRefused() {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let big = fixture.folder.appendingPathComponent("big.txt")
        try? Data(repeating: 65, count: 6 * 1024 * 1024).write(to: big)
        #expect((try? store.openFile(big)) == nil, "very large files are refused")
    }

    @Test func crlfTitlesStopAtTheLineBreak() {
        #expect(NoteNaming.title(for: "First\r\nSecond") == "First", "CRLF titles stop at the line break")
    }

    @Test @MainActor func pinningMovesNotesToTheTopAndSurvivesARestart() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let first = store.createNote()
        let second = store.createNote()
        let third = store.createNote()
        #expect(store.appNotes.map(\.id) == [third, second, first], "notes keep their order before pinning")
        store.setPinned(first, true)
        #expect(store.appNotes.map(\.id) == [first, third, second], "pinned note moves to the top")
        let newest = store.createNote()
        #expect(store.appNotes.first == store.note(first), "new notes go below pinned ones")
        store.saveNow()
        #expect(NoteStore(notesFile: cache).appNotes.map(\.id) == [first, newest, third, second], "pins survive a restart")
        store.setPinned(first, false)
        #expect(store.appNotes.map(\.id) == [newest, third, second, first], "unpinned note returns to its place")
    }

    @Test @MainActor func renamedNoteShowsItsTrimmedNameAndEmptyNameGoesBack() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "first line\nsecond")
        store.rename(id, to: "  My name  ")
        #expect(store.note(id)?.title == "My name", "a renamed note shows its trimmed name")
        #expect(store.note(id)?.snippet == "first line", "a renamed note previews its first line")
        #expect(store.note(id)?.fileName == "My name.md", "exports take the given name")
        #expect(NoteStore(notesFile: cache).note(id)?.title == "My name", "the name is saved")
        store.rename(id, to: " ")
        #expect(store.note(id)?.title == "first line", "an empty name goes back to the first line")
        store.setLocked(id, true)
        store.rename(id, to: "Locked")
        #expect(store.note(id)?.title == "first line", "a locked note keeps its name")
    }

    @Test func openedFileIsNamedByItsFile() {
        let file = Note(body: "x", localFile: LocalFile(path: "/tmp/a.md"), customTitle: "Ignored")
        #expect(file.title == "a.md", "an opened file is named by its file")
    }

    @Test @MainActor func clearingRemovesOnlyNotesWithoutAnyText() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.updateBody(id, "first line\nsecond")
        store.setLocked(id, true)
        let empty = store.createNote()
        let titled = store.createNote()
        store.updateBody(titled, "Only a title")
        let full = store.createNote()
        store.updateBody(full, "Title\nbody")
        let lockedEmpty = store.createNote()
        store.setLocked(lockedEmpty, true)
        let blank = store.createNote()
        store.updateBody(blank, "  \n\t\n")
        #expect(Set(store.emptyNotes.map(\.id)) == [empty, blank], "only notes without any text count as empty")
        store.deleteEmptyNotes([blank])
        #expect(store.note(empty) != nil && store.note(blank) == nil, "only the chosen empty notes are deleted")
        store.updateBody(empty, "typed meanwhile")
        store.deleteEmptyNotes([empty, titled, full, lockedEmpty])
        #expect(Set(store.notes.map(\.id)) == [id, empty, titled, full, lockedEmpty], "a chosen note that has text by now, a titled note and locked notes are kept")
    }

    @Test @MainActor func savingANoteAsAFileKeepsItAsThatFile() throws {
        let fixture = FileFixture()
        defer { fixture.discard() }
        let store = NoteStore(notesFile: fixture.cache)
        let id = store.createNote()
        store.updateBody(id, "# Plan\nship it")
        store.rename(id, to: "Custom")
        let existing = fixture.write("old text", to: "plan.md")
        let alreadyOpen = try store.openFile(existing)
        try store.saveAsFile(id, to: existing)
        #expect(fixture.read(existing) == "# Plan\nship it", "the note's text is written to the chosen file")
        #expect(store.note(id)?.title == "plan.md" && store.note(id)?.body == "# Plan\nship it", "the note is now named by its file")
        #expect(store.localFileNotes.map(\.id) == [id], "the note moves to the opened files, replacing the one already open there")
        #expect(store.note(alreadyOpen) == nil)
        store.updateBody(id, "# Plan\nship it today")
        store.saveNow()
        #expect(fixture.read(existing) == "# Plan\nship it today", "later edits are written to the same file")
        #expect(throws: (any Error).self, "a folder that does not exist reports an error") {
            try store.saveAsFile(store.createNote(), to: fixture.folder.appendingPathComponent("missing/x.md"))
        }
    }

    @Test @MainActor func revisionsCountEditsPerNote() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let first = store.createNote()
        let second = store.createNote()
        #expect(store.revision(of: first) == 0, "a new note starts at revision zero")
        let edited = store.updateBody(first, "# One")
        #expect(edited != nil && edited == store.revision(of: first), "an edit returns the note's new revision")
        #expect(store.updateBody(first, "# One") == nil, "the same text is not an edit")
        #expect(store.revision(of: first) == edited, "the same text leaves the revision alone")
        #expect(store.updateBody(first, "# Two") != nil, "same-length new text is still an edit")
        let other = store.updateBody(second, "# Other")
        #expect(other != nil && other! > store.revision(of: first), "revisions never repeat across notes")
        store.setLocked(first, true)
        #expect(store.updateBody(first, "# Locked") == nil, "a locked note does not take edits")
    }
}
