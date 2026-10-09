import Foundation
import HardydoNotesCore
import Testing

private func files(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

private func saveTwice(to cache: NotesFile) {
    cache.save(NotesSnapshot(notes: [Note(body: "# First")]))
    cache.save(NotesSnapshot(notes: [Note(body: "# Second")]))
}

@Suite struct NotesFileTests {
    @Test func latestSaveIsLoadedAndThePreviousOneIsKept() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let previous = NotesFile.previousVersion(of: cache.url)
        saveTwice(to: cache)
        #expect(cache.flush() == nil, "saving writes without error")
        #expect(cache.load().notes.map(\.body) == ["# Second"], "the latest save is loaded")
        #expect(NotesFile(url: previous).load().notes.map(\.body) == ["# First"], "the save before it is kept as the previous version")
        #expect(!files(in: cache.url.deletingLastPathComponent()).contains { $0.hasSuffix(".tmp") }, "no temporary file is left behind")
    }

    @Test @MainActor func damagedFileFallsBackToThePreviousVersion() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        saveTwice(to: cache)
        cache.flush()

        try? Data("{\"notes\":[{\"id\":".utf8).write(to: cache.url)
        let recovered = cache.load()
        #expect(recovered.notes.map(\.body) == ["# First"], "a damaged file falls back to the previous version")
        #expect(recovered.recoveredFromPrevious && recovered.unreadableCopy != nil, "the fallback is reported and the damaged file is copied aside")
        #expect(!recovered.loadedCleanly, "a fallback does not count as a clean load")
        let store = NoteStore(notesFile: cache)
        #expect(!store.loadedCleanly && store.fileError != nil, "the store reports notes restored from the previous version")
    }

    @Test func oneDamagedNoteDoesNotHideTheOthers() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let good = Note(body: "# Kept")
        let encoded = String(decoding: try! JSONEncoder().encode(NotesSnapshot(notes: [good])), as: UTF8.self)
        let oneBad = encoded.replacingOccurrences(of: "\"notes\":[", with: "\"notes\":[{\"body\":42},")
        try? Data(oneBad.utf8).write(to: cache.url)
        let partial = cache.load()
        #expect(partial.notes.map(\.id) == [good.id], "one damaged note does not hide the others")
        #expect(partial.skippedNotes == 1, "the damaged note is counted")
        #expect(partial.unreadableCopy != nil, "a file with a damaged note is copied aside before it can be saved over")
        #expect(cache.load().unreadableCopy != nil, "a second backup in the same second gets its own name")
    }

    @Test @MainActor func aChangeIsSavedAndSavingAgainWithoutOneDoesNotRewriteTheFile() {
        let manager = FileManager.default
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let store = NoteStore(notesFile: cache)
        let id = store.createNote()
        store.saveNow()
        #expect(manager.fileExists(atPath: cache.url.path), "a change is saved")
        try? manager.removeItem(at: cache.url)
        store.saveNow()
        #expect(!manager.fileExists(atPath: cache.url.path), "saving again without a change does not rewrite the file")
        store.updateBody(id, "# Changed")
        store.saveNow()
        #expect(manager.fileExists(atPath: cache.url.path), "the next change is saved")
    }

    @Test @MainActor func loadingAloneDoesNotRewriteTheFile() {
        let manager = FileManager.default
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        _ = NoteStore(notesFile: cache).saveNow()
        #expect(!manager.fileExists(atPath: cache.url.path), "loading alone does not rewrite the file")
    }

    @Test @MainActor func unreadableFileIsLeftUntouchedAndNewNotesGoToARecoveredFile() {
        let manager = FileManager.default
        let cache = temporaryNotesFile()
        let folder = cache.url.deletingLastPathComponent()
        defer { cache.discard() }
        let original = Data("{\"notes\":[]".utf8)
        try? original.write(to: cache.url)
        try? manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: cache.url.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cache.url.path) }

        let store = NoteStore(notesFile: cache)
        #expect(!store.loadedCleanly, "a file that cannot be read or copied is not a clean load")
        #expect(store.fileError?.contains(".recovered-") == true, "the session is saved to a separate file")
        store.createNote()
        store.saveNow()
        try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cache.url.path)
        #expect((try? Data(contentsOf: cache.url)) == original, "the unreadable file is left untouched")
        #expect(files(in: folder).filter { $0.contains(".recovered-") }.count == 1, "the new notes go to the recovered file")
    }

    @Test func cacheWithoutTheLockFieldStillLoadsAsUnlocked() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let legacy = ##"{"notes":[{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABC","body":"# Old","modifiedAt":781500000}]}"##
        try? Data(legacy.utf8).write(to: cache.url)
        let snapshot = cache.load()
        #expect(snapshot.notes.map(\.body) == ["# Old"], "cache without lock field still loads")
        #expect(snapshot.notes.first?.isLocked == false, "missing lock field means unlocked")
    }

    @Test func cacheWithOldPerNoteZoomAndSplitStillLoads() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        let perNote = ##"{"notes":[{"id":"6F1C3E2A-1B2C-4D5E-8F90-123456789ABD","body":"# Zoomed","modifiedAt":781500000,"splitRatio":0.4,"zoom":1.5}]}"##
        try? Data(perNote.utf8).write(to: cache.url)
        #expect(cache.load().notes.map(\.body) == ["# Zoomed"], "cache with old per-note zoom and split still loads")
    }

    @Test func unreadableCacheIsBackedUp() {
        let cache = temporaryNotesFile()
        defer { cache.discard() }
        try? Data("not json".utf8).write(to: cache.url)
        _ = cache.load()
        let folder = cache.url.deletingLastPathComponent()
        let prefix = cache.url.deletingPathExtension().lastPathComponent + ".unreadable-"
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasPrefix(prefix) } ?? []
        #expect(backups.count == 1, "unreadable cache is backed up")
    }
}
