import Foundation
import HardydoNotesCore

func runTrashPathChecks() {
    check(NoteStore.isInTrash("/Users/me/.Trash/note.md"), "a file in the user Trash is in the Trash")
    check(NoteStore.isInTrash("/Volumes/Disk/.Trashes/501/note.md"), "a file in a volume Trash is in the Trash")
    check(!NoteStore.isInTrash("/Users/me/Notes/.Trash-notes/note.md"), "a folder only named like the Trash is not")
    check(!NoteStore.isInTrash("/Users/me/Notes/note.md"), "a regular file is not in the Trash")
}

let checksFolder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-checks-\(UUID().uuidString)")

/// Each in its own folder, since a save also leaves the previous version beside the file.
func temporaryNotesFile() -> NotesFile {
    let folder = checksFolder.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return NotesFile(url: folder.appendingPathComponent("notes.json"))
}

@MainActor
func runStoreChecks() async {
    let cache = temporaryNotesFile()
    defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
    let store = NoteStore(notesFile: cache)
    let id = store.createNote()
    store.updateBody(id, "# Groceries\nmilk")
    store.updateBody(id, "# Groceries\nmilk\nbread")
    try? await Task.sleep(for: .milliseconds(600))
    checkEqual(NoteStore(notesFile: cache).note(id)?.body, "# Groceries\nmilk\nbread", "edits are saved shortly after typing")

    let other = store.createNote()
    store.updateBody(other, "# Other")
    store.saveNow()
    checkEqual(NoteStore(notesFile: cache).notes.map(\.title), ["Other", "Groceries"], "save now writes every note")

    store.delete(id)
    check(store.note(id) == nil, "delete removes the note")
    checkEqual(NoteStore(notesFile: cache).notes.map(\.id), [other], "deleting is saved")
    store.close(other)
    check(store.note(other) != nil, "closing applies only to opened files")
}

@MainActor
func runLockChecks() async {
    let cache = temporaryNotesFile()
    defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
    let store = NoteStore(notesFile: cache)
    let id = store.createNote()
    store.updateBody(id, "# Locked\noriginal")
    store.setLocked(id, true)
    store.updateBody(id, "# Locked\nchanged")
    checkEqual(store.note(id)?.body, "# Locked\noriginal", "locked note cannot be edited")
    store.delete(id)
    check(store.note(id) != nil, "locked note cannot be deleted")
    checkEqual(NoteStore(notesFile: cache).note(id)?.isLocked, true, "lock is saved locally")
    store.setLocked(id, false)
    store.updateBody(id, "# Locked\nchanged")
    checkEqual(store.note(id)?.body, "# Locked\nchanged", "unlocked note can be edited")
}

@MainActor
func runOrderAndFileChecks() async {
    let cache = temporaryNotesFile()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-files-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: folder)
    }

    let older = Note(body: "# Older", modifiedAt: Date(timeIntervalSince1970: 1_000))
    let newer = Note(body: "# Newer", modifiedAt: Date(timeIntervalSince1970: 2_000))
    let legacy = ##"{"notes":[\##(String(decoding: try! JSONEncoder().encode(older), as: UTF8.self)),\##(String(decoding: try! JSONEncoder().encode(newer), as: UTF8.self))]}"##
    try? Data(legacy.utf8).write(to: cache.url)
    let store = NoteStore(notesFile: cache)
    checkEqual(store.notes.map(\.title), ["Newer", "Older"], "old cache keeps newest-first order")

    let fresh = store.createNote()
    checkEqual(store.notes.first?.id, fresh, "new note goes to the top")
    store.move(fromOffsets: [0], toOffset: 3)
    checkEqual(store.notes.map(\.title), ["Newer", "Older", NoteNaming.untitled], "dragging a note moves it")
    store.move(fromOffsets: [1], toOffset: 0)
    checkEqual(store.notes.map(\.title), ["Older", "Newer", NoteNaming.untitled], "dragging up moves it up")
    store.saveNow()
    checkEqual(NoteStore(notesFile: cache).notes.map(\.title), ["Older", "Newer", NoteNaming.untitled], "custom order is saved")

    let url = folder.appendingPathComponent("todo.txt")
    try? "buy milk\ncall mom".write(to: url, atomically: true, encoding: .utf8)
    let opened = try? store.openFile(url)
    checkEqual(opened.flatMap(store.note)?.body, "buy milk\ncall mom", "opening a text file shows its content")
    checkEqual(opened.flatMap(store.note)?.title, "todo.txt", "file note is titled by file name")
    checkEqual(store.notes.first?.id, opened, "opened file goes to the top")
    checkEqual(try? store.openFile(url), opened, "opening the same file again reuses its note")
    checkEqual(store.localFileNotes.map(\.id), [opened!], "opened files are listed apart")
    check(!store.appNotes.contains { $0.id == opened }, "opened files are not app notes")

    store.updateBody(opened!, "buy milk\ncall mom\npay rent")
    store.saveNow()
    checkEqual(try? String(contentsOf: url, encoding: .utf8), "buy milk\ncall mom\npay rent", "edits are written to the file")
    store.updateBody(opened!, "buy milk\ncall mom\npay rent\nwater plants")
    try? await Task.sleep(for: .milliseconds(800))
    checkEqual(try? String(contentsOf: url, encoding: .utf8), "buy milk\ncall mom\npay rent\nwater plants", "edits reach the file shortly after typing, written off the main thread")
    check(store.note(opened!)?.localFile?.needsSave == false, "a finished background write clears the pending flag")
    store.updateBody(opened!, "buy milk\ncall mom\npay rent")
    store.saveNow()

    try? "changed elsewhere".write(to: url, atomically: true, encoding: .utf8)
    _ = try? store.openFile(url)
    checkEqual(store.note(opened!)?.body, "changed elsewhere", "reopening picks up changes made outside the app")
    try? "changed while closed".write(to: url, atomically: true, encoding: .utf8)
    let relaunched = NoteStore(notesFile: cache)
    checkEqual(relaunched.note(opened!)?.body, "changed elsewhere", "launch shows the saved text before checking files")
    await relaunched.refreshLocalFiles()
    checkEqual(relaunched.note(opened!)?.body, "changed while closed", "file content is reloaded after launch")
    try? "changed elsewhere".write(to: url, atomically: true, encoding: .utf8)
    _ = try? store.openFile(url)

    store.delete(opened!)
    check(store.note(opened!) != nil, "delete does not remove a file note")
    store.updateBody(opened!, "last edit")
    store.close(opened!)
    check(store.note(opened!) == nil, "closing takes the file off the list")
    checkEqual(try? String(contentsOf: url, encoding: .utf8), "last edit", "closing writes pending edits and keeps the file")

    check((try? store.openFile(folder)) == nil, "folders are not opened as notes")
}

@MainActor
func runFileSafetyChecks() async {
    let cache = temporaryNotesFile()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-safety-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: folder)
    }
    let store = NoteStore(notesFile: cache)
    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    var shared = folder.appendingPathComponent("shared.md")
    try? "v1".write(to: shared, atomically: true, encoding: .utf8)
    let original = Date(timeIntervalSince1970: 946_684_800)
    var values = URLResourceValues()
    values.creationDate = original
    try? shared.setResourceValues(values)
    let id = try! store.openFile(shared)
    store.updateBody(id, "app edit")
    try? "other app".write(to: shared, atomically: true, encoding: .utf8)
    try? shared.setResourceValues(values)
    store.saveNow()
    checkEqual(store.fileConflict?.id, id, "a file changed by another app is reported as a conflict")
    checkEqual(read(shared), "other app", "the other app's version is not overwritten")
    check(store.note(id)?.localFile?.needsSave == true, "unsaved edits are kept during a conflict")
    store.resolveFileConflict(keepAppVersion: true)
    store.saveNow()
    checkEqual(read(shared), "app edit", "keeping the app version writes it")
    shared.removeAllCachedResourceValues()
    checkEqual((try? shared.resourceValues(forKeys: [.creationDateKey]))?.creationDate, original, "saving keeps the file's creation date")

    store.updateBody(id, "second edit")
    try? "disk wins".write(to: shared, atomically: true, encoding: .utf8)
    store.saveNow()
    store.resolveFileConflict(keepAppVersion: false)
    checkEqual(store.note(id)?.body, "disk wins", "using the disk version replaces the app text")
    check(store.note(id)?.localFile?.needsSave == false, "using the disk version clears pending edits")

    let beforeRefresh = store.revision(of: id)
    try? "refreshed".write(to: shared, atomically: true, encoding: .utf8)
    await store.refreshLocalFiles()
    checkEqual(store.note(id)?.body, "refreshed", "outside changes load when the app becomes active")
    check(store.revision(of: id) > beforeRefresh, "text loaded from disk moves the revision, so the editor shows it")

    try? "disk again".write(to: shared, atomically: true, encoding: .utf8)
    let racing = Task { await store.refreshLocalFiles() }
    await Task.yield()
    store.updateBody(id, "typed meanwhile")
    await racing.value
    checkEqual(store.note(id)?.body, "typed meanwhile", "a check that began before an edit leaves the edit alone")
    await store.refreshLocalFiles()
    checkEqual(store.fileConflict?.id, id, "the next check reports the outside change as a conflict with the unsaved edit")
    store.resolveFileConflict(keepAppVersion: true)
    store.saveNow()
    checkEqual(read(shared), "typed meanwhile", "keeping the app version after a check writes it")

    let missing = folder.appendingPathComponent("gone.txt")
    try? "x".write(to: missing, atomically: true, encoding: .utf8)
    let gone = try! store.openFile(missing)
    try? FileManager.default.removeItem(at: missing)
    store.updateBody(gone, "unsaved")
    store.saveNow()
    check(store.fileError != nil, "a missing file reports a save error")
    check(store.note(gone)?.localFile?.needsSave == true, "edits to a missing file are kept")
    store.dismissFileError()
    store.close(gone)
    check(store.note(gone) != nil && store.fileError != nil, "a note with unsaved file edits is not closed")
    store.dismissFileError()

    let utf16 = folder.appendingPathComponent("utf16.txt")
    try? "Café déjà vu".write(to: utf16, atomically: true, encoding: .utf16)
    let wide = try! store.openFile(utf16)
    checkEqual(store.note(wide)?.body, "Café déjà vu", "UTF-16 files are read")
    store.updateBody(wide, "Naïve résumé")
    store.saveNow()
    checkEqual(try? String(contentsOf: utf16, encoding: .utf16), "Naïve résumé", "files are saved in their original encoding")

    let big = folder.appendingPathComponent("big.txt")
    try? Data(repeating: 65, count: 6 * 1024 * 1024).write(to: big)
    check((try? store.openFile(big)) == nil, "very large files are refused")

    checkEqual(NoteNaming.title(for: "First\r\nSecond"), "First", "CRLF titles stop at the line break")
}

@MainActor
func runPinChecks() async {
    let cache = temporaryNotesFile()
    defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
    let store = NoteStore(notesFile: cache)
    let first = store.createNote()
    let second = store.createNote()
    let third = store.createNote()
    checkEqual(store.appNotes.map(\.id), [third, second, first], "notes keep their order before pinning")
    store.setPinned(first, true)
    checkEqual(store.appNotes.map(\.id), [first, third, second], "pinned note moves to the top")
    let newest = store.createNote()
    checkEqual(store.appNotes.first, store.note(first), "new notes go below pinned ones")
    store.saveNow()
    checkEqual(NoteStore(notesFile: cache).appNotes.map(\.id), [first, newest, third, second], "pins survive a restart")
    store.setPinned(first, false)
    checkEqual(store.appNotes.map(\.id), [newest, third, second, first], "unpinned note returns to its place")
}

@MainActor
func runRenameChecks() {
    let cache = temporaryNotesFile()
    defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
    let store = NoteStore(notesFile: cache)
    let id = store.createNote()
    store.updateBody(id, "first line\nsecond")
    store.rename(id, to: "  My name  ")
    checkEqual(store.note(id)?.title, "My name", "a renamed note shows its trimmed name")
    checkEqual(store.note(id)?.snippet, "first line", "a renamed note previews its first line")
    checkEqual(store.note(id)?.fileName, "My name.md", "exports take the given name")
    checkEqual(NoteStore(notesFile: cache).note(id)?.title, "My name", "the name is saved")
    store.rename(id, to: " ")
    checkEqual(store.note(id)?.title, "first line", "an empty name goes back to the first line")
    store.setLocked(id, true)
    store.rename(id, to: "Locked")
    checkEqual(store.note(id)?.title, "first line", "a locked note keeps its name")

    let file = Note(body: "x", localFile: LocalFile(path: "/tmp/a.md"), customTitle: "Ignored")
    checkEqual(file.title, "a.md", "an opened file is named by its file")

    let empty = store.createNote()
    let titled = store.createNote()
    store.updateBody(titled, "Only a title")
    let full = store.createNote()
    store.updateBody(full, "Title\nbody")
    let lockedEmpty = store.createNote()
    store.setLocked(lockedEmpty, true)
    let blank = store.createNote()
    store.updateBody(blank, "  \n\t\n")
    checkEqual(Set(store.emptyNotes.map(\.id)), [empty, blank], "only notes without any text count as empty")
    store.deleteEmptyNotes()
    checkEqual(Set(store.notes.map(\.id)), [id, titled, full, lockedEmpty], "clearing keeps notes with a title line and locked notes")
}

/// Saves still debounced when a check returns land later, so the folder is removed once every queued write is done.
func removeChecksFolder() {
    NotesFile(url: checksFolder).flush()
    try? FileManager.default.removeItem(at: checksFolder)
}

@MainActor
func runRevisionChecks() {
    let cache = temporaryNotesFile()
    defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
    let store = NoteStore(notesFile: cache)
    let first = store.createNote()
    let second = store.createNote()
    checkEqual(store.revision(of: first), 0, "a new note starts at revision zero")
    let edited = store.updateBody(first, "# One")
    check(edited != nil && edited == store.revision(of: first), "an edit returns the note's new revision")
    check(store.updateBody(first, "# One") == nil, "the same text is not an edit")
    checkEqual(store.revision(of: first), edited, "the same text leaves the revision alone")
    check(store.updateBody(first, "# Two") != nil, "same-length new text is still an edit")
    let other = store.updateBody(second, "# Other")
    check(other != nil && other! > store.revision(of: first), "revisions never repeat across notes")
    store.setLocked(first, true)
    check(store.updateBody(first, "# Locked") == nil, "a locked note does not take edits")
}
