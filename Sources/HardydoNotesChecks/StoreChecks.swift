import HardydoNotesCore
import Foundation

private func temporaryCache() -> NoteCache {
    NoteCache(url: FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-checks-\(UUID().uuidString).json"))
}

@MainActor
func runStoreChecks() async {
    let cache = temporaryCache()
    defer { try? FileManager.default.removeItem(at: cache.url) }
    let store = NoteStore(cache: cache)
    let id = store.createNote()
    store.updateBody(id, "# Groceries\nmilk")
    store.updateBody(id, "# Groceries\nmilk\nbread")
    try? await Task.sleep(for: .milliseconds(600))
    checkEqual(NoteStore(cache: cache).note(id)?.body, "# Groceries\nmilk\nbread", "edits are saved shortly after typing")

    let other = store.createNote()
    store.updateBody(other, "# Other")
    store.saveNow()
    checkEqual(NoteStore(cache: cache).notes.map(\.title), ["Other", "Groceries"], "save now writes every note")

    store.delete(id)
    check(store.note(id) == nil, "delete removes the note")
    checkEqual(NoteStore(cache: cache).notes.map(\.id), [other], "deleting is saved")
    store.close(other)
    check(store.note(other) != nil, "closing applies only to opened files")
}

@MainActor
func runLockChecks() async {
    let cache = temporaryCache()
    defer { try? FileManager.default.removeItem(at: cache.url) }
    let store = NoteStore(cache: cache)
    let id = store.createNote()
    store.updateBody(id, "# Locked\noriginal")
    store.setLocked(id, true)
    store.updateBody(id, "# Locked\nchanged")
    checkEqual(store.note(id)?.body, "# Locked\noriginal", "locked note cannot be edited")
    store.delete(id)
    check(store.note(id) != nil, "locked note cannot be deleted")
    checkEqual(NoteStore(cache: cache).note(id)?.isLocked, true, "lock is saved locally")
    store.setLocked(id, false)
    store.updateBody(id, "# Locked\nchanged")
    checkEqual(store.note(id)?.body, "# Locked\nchanged", "unlocked note can be edited")
}

func runCacheCompatibilityChecks() {
    let cache = temporaryCache()
    defer { try? FileManager.default.removeItem(at: cache.url) }
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

@MainActor
func runOrderAndFileChecks() async {
    let cache = temporaryCache()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-files-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: cache.url)
        try? FileManager.default.removeItem(at: folder)
    }

    let older = Note(body: "# Older", modifiedAt: Date(timeIntervalSince1970: 1_000))
    let newer = Note(body: "# Newer", modifiedAt: Date(timeIntervalSince1970: 2_000))
    let legacy = ##"{"notes":[\##(String(decoding: try! JSONEncoder().encode(older), as: UTF8.self)),\##(String(decoding: try! JSONEncoder().encode(newer), as: UTF8.self))]}"##
    try? Data(legacy.utf8).write(to: cache.url)
    let store = NoteStore(cache: cache)
    checkEqual(store.notes.map(\.title), ["Newer", "Older"], "old cache keeps newest-first order")

    let fresh = store.createNote()
    checkEqual(store.notes.first?.id, fresh, "new note goes to the top")
    store.move(fromOffsets: [0], toOffset: 3)
    checkEqual(store.notes.map(\.title), ["Newer", "Older", NoteNaming.untitled], "dragging a note moves it")
    store.move(fromOffsets: [1], toOffset: 0)
    checkEqual(store.notes.map(\.title), ["Older", "Newer", NoteNaming.untitled], "dragging up moves it up")
    store.saveNow()
    checkEqual(NoteStore(cache: cache).notes.map(\.title), ["Older", "Newer", NoteNaming.untitled], "custom order is saved")

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

    try? "changed elsewhere".write(to: url, atomically: true, encoding: .utf8)
    _ = try? store.openFile(url)
    checkEqual(store.note(opened!)?.body, "changed elsewhere", "reopening picks up changes made outside the app")
    checkEqual(NoteStore(cache: cache).note(opened!)?.body, "changed elsewhere", "file content is reloaded on launch")

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
    let cache = temporaryCache()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-safety-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: cache.url)
        try? FileManager.default.removeItem(at: folder)
    }
    let store = NoteStore(cache: cache)
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

    try? "refreshed".write(to: shared, atomically: true, encoding: .utf8)
    store.refreshLocalFiles()
    checkEqual(store.note(id)?.body, "refreshed", "outside changes load when the app becomes active")

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
func runSearchChecks() async {
    func ranges(_ query: String, _ text: String, _ options: SearchOptions = SearchOptions()) -> [String] {
        guard let expression = try? TextSearch.expression(for: query, options: options) else { return ["<invalid>"] }
        return TextSearch.matches(of: expression, in: text).map { (text as NSString).substring(with: $0) }
    }
    checkEqual(ranges("note", "Note note NOTE"), ["Note", "note", "NOTE"], "search ignores case by default")
    checkEqual(ranges("note", "Note note", SearchOptions(caseSensitive: true)), ["note"], "case-sensitive search")
    checkEqual(ranges("cat", "cat concat cat_ (cat)", SearchOptions(wholeWord: true)), ["cat", "cat"], "whole word skips parts of words")
    checkEqual(ranges("c++", "c++ and c++x", SearchOptions(wholeWord: true)), ["c++"], "whole word works next to punctuation")
    checkEqual(ranges("café", "Café time, cafés", SearchOptions(wholeWord: true)), ["Café"], "whole word understands accented letters")
    checkEqual(ranges("a.c", "abc a.c"), ["a.c"], "plain search treats symbols literally")
    checkEqual(ranges("a.c", "abc a.c", SearchOptions(regex: true)), ["abc", "a.c"], "regex search")
    checkEqual(ranges("^- ", "- one\n- two\nx - three", SearchOptions(regex: true)), ["- ", "- "], "regex anchors match each line")
    checkEqual(ranges("x*", "aaa", SearchOptions(regex: true)), [], "empty regex matches are skipped")
    checkEqual(ranges("(", "(", SearchOptions(regex: true)), ["<invalid>"], "bad regex is reported")
    check((try? TextSearch.expression(for: "", options: SearchOptions())) == .some(nil), "empty query searches nothing")

    let text = "intro\r\n  find me here\n\nlast find"
    let expression = try! TextSearch.expression(for: "find", options: SearchOptions())!
    let lines = TextSearch.lineMatches(of: expression, in: text, limit: 10)
    checkEqual(lines.map(\.line), [2, 4], "line numbers count every kind of line break")
    checkEqual(lines.first.map { [$0.before, $0.matched, $0.after] }, ["", "find", " me here"], "line snippet splits around the match")
    checkEqual(lines.last.map { [$0.before, $0.after] }, ["last ", ""], "line snippet at the end of the text")
    checkEqual(TextSearch.lineMatches(of: expression, in: text, limit: 1).count, 1, "line matches respect the limit")

    let regex = try! TextSearch.expression(for: "(\\w+)@(\\w+)", options: SearchOptions(regex: true))!
    let mail = "mail a@b now"
    let range = TextSearch.matches(of: regex, in: mail)[0]
    checkEqual(TextSearch.replacement(for: range, in: mail, expression: regex, template: "$2 at $1", options: SearchOptions(regex: true)), "b at a", "regex replace uses groups")
    let literal = try! TextSearch.expression(for: "cost", options: SearchOptions())!
    let price = "cost: cost"
    checkEqual(TextSearch.replacement(for: TextSearch.matches(of: literal, in: price)[1], in: price, expression: literal, template: "$5", options: SearchOptions()), "$5", "plain replace inserts text as typed")
    checkEqual(TextSearch.replacement(for: NSRange(location: 1, length: 3), in: price, expression: literal, template: "x", options: SearchOptions()), nil, "stale range is not replaced")
    let all = TextSearch.replacingAll(in: "a-b-c", expression: try! TextSearch.expression(for: "-", options: SearchOptions())!, template: "+", options: SearchOptions())
    check(all.text == "a+b+c" && all.count == 2, "replace all")
    let word = try! TextSearch.expression(for: "cat", options: SearchOptions(wholeWord: true))!
    let pets = "concat cat"
    checkEqual(TextSearch.replacement(for: NSRange(location: 7, length: 3), in: pets, expression: word, template: "dog", options: SearchOptions(wholeWord: true)), "dog", "single replace sees the text around the match")
}

@MainActor
func runPinChecks() async {
    let cache = temporaryCache()
    defer { try? FileManager.default.removeItem(at: cache.url) }
    let store = NoteStore(cache: cache)
    let first = store.createNote()
    let second = store.createNote()
    let third = store.createNote()
    checkEqual(store.appNotes.map(\.id), [third, second, first], "notes keep their order before pinning")
    store.setPinned(first, true)
    checkEqual(store.appNotes.map(\.id), [first, third, second], "pinned note moves to the top")
    let newest = store.createNote()
    checkEqual(store.appNotes.first, store.note(first), "new notes go below pinned ones")
    store.saveNow()
    checkEqual(NoteStore(cache: cache).appNotes.map(\.id), [first, newest, third, second], "pins survive a restart")
    store.setPinned(first, false)
    checkEqual(store.appNotes.map(\.id), [newest, third, second, first], "unpinned note returns to its place")
}

@MainActor
func runRenameChecks() {
    let cache = temporaryCache()
    defer { try? FileManager.default.removeItem(at: cache.url) }
    let store = NoteStore(cache: cache)
    let id = store.createNote()
    store.updateBody(id, "first line\nsecond")
    store.rename(id, to: "  My name  ")
    checkEqual(store.note(id)?.title, "My name", "a renamed note shows its trimmed name")
    checkEqual(store.note(id)?.snippet, "first line", "a renamed note previews its first line")
    checkEqual(store.note(id)?.fileName, "My name.md", "exports take the given name")
    checkEqual(NoteStore(cache: cache).note(id)?.title, "My name", "the name is saved")
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
