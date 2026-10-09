import Foundation
import HardydoNotesCore

private func files(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

@MainActor
func runNotesFileChecks() async {
    let manager = FileManager.default
    let cache = temporaryNotesFile()
    let folder = cache.url.deletingLastPathComponent()
    defer { try? manager.removeItem(at: folder) }
    let previous = NotesFile.previousVersion(of: cache.url)

    cache.save(NotesSnapshot(notes: [Note(body: "# First")]))
    cache.save(NotesSnapshot(notes: [Note(body: "# Second")]))
    check(cache.flush() == nil, "saving writes without error")
    checkEqual(cache.load().notes.map(\.body), ["# Second"], "the latest save is loaded")
    checkEqual(NotesFile(url: previous).load().notes.map(\.body), ["# First"], "the save before it is kept as the previous version")
    check(!files(in: folder).contains { $0.hasSuffix(".tmp") }, "no temporary file is left behind")

    try? Data("{\"notes\":[{\"id\":".utf8).write(to: cache.url)
    let recovered = cache.load()
    checkEqual(recovered.notes.map(\.body), ["# First"], "a damaged file falls back to the previous version")
    check(recovered.recoveredFromPrevious && recovered.unreadableCopy != nil, "the fallback is reported and the damaged file is copied aside")
    check(!recovered.loadedCleanly, "a fallback does not count as a clean load")
    let store = NoteStore(notesFile: cache)
    check(!store.loadedCleanly && store.fileError != nil, "the store reports notes restored from the previous version")
    for name in files(in: folder) where name.contains(".unreadable-") {
        try? manager.removeItem(at: folder.appendingPathComponent(name))
    }

    let good = Note(body: "# Kept")
    let encoded = String(decoding: try! JSONEncoder().encode(NotesSnapshot(notes: [good])), as: UTF8.self)
    let oneBad = encoded.replacingOccurrences(of: "\"notes\":[", with: "\"notes\":[{\"body\":42},")
    try? Data(oneBad.utf8).write(to: cache.url)
    let partial = cache.load()
    checkEqual(partial.notes.map(\.id), [good.id], "one damaged note does not hide the others")
    checkEqual(partial.skippedNotes, 1, "the damaged note is counted")
    check(partial.unreadableCopy != nil, "a file with a damaged note is copied aside before it can be saved over")
    check(cache.load().unreadableCopy != nil, "a second backup in the same second gets its own name")
}

@MainActor
func runSaveSkippingChecks() {
    let manager = FileManager.default
    let cache = temporaryNotesFile()
    defer { try? manager.removeItem(at: cache.url.deletingLastPathComponent()) }
    let store = NoteStore(notesFile: cache)
    let id = store.createNote()
    store.saveNow()
    check(manager.fileExists(atPath: cache.url.path), "a change is saved")
    try? manager.removeItem(at: cache.url)
    store.saveNow()
    check(!manager.fileExists(atPath: cache.url.path), "saving again without a change does not rewrite the file")
    store.updateBody(id, "# Changed")
    store.saveNow()
    check(manager.fileExists(atPath: cache.url.path), "the next change is saved")

    try? manager.removeItem(at: cache.url)
    _ = NoteStore(notesFile: cache).saveNow()
    check(!manager.fileExists(atPath: cache.url.path), "loading alone does not rewrite the file")
}

@MainActor
func runUnreadableInPlaceChecks() {
    let manager = FileManager.default
    let cache = temporaryNotesFile()
    let folder = cache.url.deletingLastPathComponent()
    defer { try? manager.removeItem(at: folder) }
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let original = Data("{\"notes\":[]".utf8)
    try? original.write(to: cache.url)
    try? manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: cache.url.path)
    defer { try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cache.url.path) }

    let store = NoteStore(notesFile: cache)
    check(!store.loadedCleanly, "a file that cannot be read or copied is not a clean load")
    check(store.fileError?.contains(".recovered-") == true, "the session is saved to a separate file")
    store.createNote()
    store.saveNow()
    try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cache.url.path)
    checkEqual(try? Data(contentsOf: cache.url), original, "the unreadable file is left untouched")
    checkEqual(files(in: folder).filter { $0.contains(".recovered-") }.count, 1, "the new notes go to the recovered file")
}

func runCacheCompatibilityChecks() {
    let cache = temporaryNotesFile()
    defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
    let legacy = ##"{"notes":[{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABC","body":"# Old","modifiedAt":781500000}]}"##
    try? FileManager.default.createDirectory(at: cache.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(legacy.utf8).write(to: cache.url)
    let snapshot = cache.load()
    checkEqual(snapshot.notes.map(\.body), ["# Old"], "cache without lock field still loads")
    checkEqual(snapshot.notes.first?.isLocked, false, "missing lock field means unlocked")

    let perNote = ##"{"notes":[{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABD","body":"# Zoomed","modifiedAt":781500000,"splitRatio":0.4,"zoom":1.5}]}"##
    try? Data(perNote.utf8).write(to: cache.url)
    checkEqual(cache.load().notes.map(\.body), ["# Zoomed"], "cache with old per-note zoom and split still loads")

    try? Data("not json".utf8).write(to: cache.url)
    _ = cache.load()
    let folder = cache.url.deletingLastPathComponent()
    let prefix = cache.url.deletingPathExtension().lastPathComponent + ".unreadable-"
    let backups = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasPrefix(prefix) } ?? []
    checkEqual(backups.count, 1, "unreadable cache is backed up")
    backups.forEach { try? FileManager.default.removeItem(at: folder.appendingPathComponent($0)) }
}
