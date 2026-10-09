import Foundation
import Observation

public struct FileConflict: Equatable, Sendable {
    public let id: Note.ID
    public let name: String
}

public enum FileOpenError: LocalizedError, Equatable {
    case notText(String)
    case tooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .notText(let name): "“\(name)” is not a plain text file."
        case .tooLarge(let name): "“\(name)” is larger than 5 MB, too large to open."
        }
    }
}

@MainActor
@Observable
public final class NoteStore {
    public private(set) var notes: [Note] = [] {
        didSet { changeCount &+= 1 }
    }
    public private(set) var fileConflict: FileConflict?
    /// Moves on with every change to the list or to any note, so work that reads them all knows when to run again.
    public private(set) var changeCount = 0
    public private(set) var fileError: String?
    /// False when the notes file was damaged, so whatever is kept beside it (groups, tabs) must not be pruned against this list.
    @ObservationIgnored public private(set) var loadedCleanly = true

    @ObservationIgnored private var notesFile: NotesFile
    @ObservationIgnored private var cacheTask: Task<Void, Never>?
    @ObservationIgnored private var failedFileWrites: Set<Note.ID> = []
    @ObservationIgnored private var revisions: [Note.ID: Int] = [:]
    @ObservationIgnored private var lastRevision = 0
    @ObservationIgnored private var savedCount: Int? = 0
    /// Every read and write of opened files, in order, so a check never runs while the store's own write is half done.
    @ObservationIgnored private let diskQueue = DispatchQueue(label: "com.hardydo.notes.files", qos: .userInitiated)
    @ObservationIgnored private let finishedWrites = FileWriteInbox()
    @ObservationIgnored private var writing: Set<Note.ID> = []
    @ObservationIgnored private var positions: [Note.ID: Int] = [:]
    @ObservationIgnored private var positionsChange = -1

    public init(notesFile: NotesFile) {
        self.notesFile = notesFile
        let snapshot = notesFile.load()
        // Notes files from before manual ordering kept notes in creation order and showed them newest first.
        notes = snapshot.isOrdered ? snapshot.notes : snapshot.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        loadedCleanly = snapshot.loadedCleanly
        fileError = Self.loadProblem(snapshot, at: notesFile.url)
        if snapshot.isUnreadableInPlace {
            self.notesFile = NotesFile(url: notesFile.url.deletingPathExtension().appendingPathExtension("recovered-\(Int(Date().timeIntervalSince1970)).json"))
            fileError = (fileError ?? "") + " This session is saved to \(self.notesFile.url.path) instead."
        }
        savedCount = changeCount
    }

    private static func loadProblem(_ snapshot: NotesSnapshot, at url: URL) -> String? {
        let kept = " Groups and tabs are not saved until the notes file loads normally."
        if snapshot.recoveredFromPrevious {
            let copy = snapshot.unreadableCopy.map { " The unreadable file was kept at \($0.path)." } ?? ""
            return "Your notes file could not be read, so the notes from the save before it were restored." + copy + kept
        }
        if snapshot.skippedNotes > 0 {
            let copy = snapshot.unreadableCopy.map { " The original file was kept at \($0.path)." } ?? ""
            return "\(snapshot.skippedNotes) damaged \(snapshot.skippedNotes == 1 ? "note" : "notes") could not be read and \(snapshot.skippedNotes == 1 ? "is" : "are") left out." + copy + kept
        }
        if let copy = snapshot.unreadableCopy {
            return "Your notes file could not be read, so the list starts empty. The unreadable file was kept at \(copy.path)." + kept
        }
        if snapshot.isUnreadableInPlace {
            return "Your notes file at \(url.path) could not be read or copied, so the list starts empty and the file is left untouched." + kept
        }
        return nil
    }

    /// Moves on whenever a note's text changes, so a view can tell new text from the text it holds without comparing them.
    public func revision(of id: Note.ID) -> Int {
        revisions[id] ?? 0
    }

    private func bumpRevision(_ id: Note.ID) -> Int {
        lastRevision += 1
        revisions[id] = lastRevision
        return lastRevision
    }

    public func text(of note: Note) -> NoteText {
        NoteText(note: note.id, revision: revision(of: note.id), string: note.body)
    }

    /*
     Edits nearly always change the length, which is free to read from editor text and settles it. Otherwise the
     UTF-16 units are compared as they are; String == would normalize both texts first, which is far slower.
     */
    private static func differs(_ old: String, _ new: String) -> Bool {
        old.utf16.count != new.utf16.count || !(old as NSString).isEqual(to: new)
    }

    public func note(_ id: Note.ID) -> Note? {
        index(of: id).map { notes[$0] }
    }

    /// Answers from a map of positions that is only rebuilt when it turns out stale, so lookups stay O(1) while typing.
    public func index(of id: Note.ID) -> Int? {
        if let index = positions[id], index < notes.count, notes[index].id == id { return index }
        guard positionsChange != changeCount else { return nil }
        positions = Dictionary(notes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        positionsChange = changeCount
        return positions[id]
    }

    @discardableResult
    public func createNote() -> Note.ID {
        let note = Note()
        notes.insert(note, at: 0)
        persistSoon()
        return note.id
    }

    /// Notes kept in the app; files opened from disk are listed apart.
    public var appNotes: [Note] {
        pinnedFirst(notes.filter { $0.localFile == nil })
    }

    public var localFileNotes: [Note] {
        pinnedFirst(notes.filter { $0.localFile != nil })
    }

    private func pinnedFirst(_ notes: [Note]) -> [Note] {
        notes.filter(\.isPinned) + notes.filter { !$0.isPinned }
    }

    public func setPinned(_ id: Note.ID, _ pinned: Bool) {
        guard let index = self.index(of: id), notes[index].isPinned != pinned else { return }
        notes[index].isPinned = pinned
        persist()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { notes[$0] }
        var remaining = notes.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        notes = remaining
        persistSoon()
    }

    /// Puts notes in the given order; notes left out keep their place after them.
    public func reorder(_ order: [Note.ID]) {
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = notes.enumerated().sorted { lhs, rhs in
            (position[lhs.element.id] ?? order.count + lhs.offset) < (position[rhs.element.id] ?? order.count + rhs.offset)
        }.map(\.element)
        guard sorted.map(\.id) != notes.map(\.id) else { return }
        notes = sorted
        persistSoon()
    }

    public func openFile(_ url: URL, at position: Int = 0) throws -> Note.ID {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        if let note = notes.first(where: { $0.localFile?.path == url.path }) {
            waitForFileWrites()
            if let job = fileJob(note.id) { apply(LocalFileDisk.check(job)) }
            persist()
            return note.id
        }
        let (text, encoding) = try LocalFileDisk.readText(url)
        let file = LocalFile(path: url.path, bookmark: try? url.bookmarkData(), stamp: LocalFileDisk.stamp(url), encoding: encoding.rawValue)
        let note = Note(body: text, modifiedAt: Date(), localFile: file)
        notes.insert(note, at: min(max(position, 0), notes.count))
        persist()
        return note.id
    }

    /*
     Checks every opened file on the disk queue and loads the ones changed elsewhere. A note edited, or written,
     while the check ran is left for the next one, which then sees the edit and reports a conflict instead.
     */
    public func refreshLocalFiles() async {
        let jobs = notes.compactMap { fileJob($0.id) }
        guard !jobs.isEmpty else { return }
        let checks = await withCheckedContinuation { continuation in
            diskQueue.async { continuation.resume(returning: jobs.map(LocalFileDisk.check)) }
        }
        let before = changeCount
        checks.forEach(apply)
        if changeCount != before { persistSoon() }
    }

    private func fileJob(_ id: Note.ID) -> FileJob? {
        guard !writing.contains(id), let note = note(id), let file = note.localFile else { return nil }
        return FileJob(id: id, revision: revision(of: id), file: file)
    }

    private func apply(_ check: LocalFileDisk.Check) {
        let id = check.job.id
        guard !writing.contains(id), let index = self.index(of: id), notes[index].localFile == check.job.file,
              revision(of: id) == check.job.revision, let location = check.location else { return }
        if let moved = location.moved { notes[index].localFile = moved }
        guard check.stamp != check.job.file.stamp else { return }
        if check.job.file.needsSave {
            fileConflict = FileConflict(id: id, name: notes[index].title)
        } else if let disk = check.disk {
            takeDiskText(disk.text, at: index)
            notes[index].localFile?.encoding = disk.encoding
            notes[index].localFile?.stamp = check.stamp
        }
    }

    public func resolveFileConflict(keepAppVersion: Bool) {
        guard let conflict = fileConflict else { return }
        fileConflict = nil
        waitForFileWrites()
        guard let index = self.index(of: conflict.id), let file = notes[index].localFile,
              let location = LocalFileDisk.locate(file) else { return }
        if let moved = location.moved { notes[index].localFile = moved }
        if keepAppVersion {
            notes[index].localFile?.stamp = LocalFileDisk.stamp(location.url)
            notes[index].localFile?.needsSave = true
        } else if let (text, encoding) = try? LocalFileDisk.readText(location.url) {
            takeDiskText(text, at: index)
            notes[index].localFile?.encoding = encoding.rawValue
            notes[index].localFile?.stamp = LocalFileDisk.stamp(location.url)
            notes[index].localFile?.needsSave = false
        }
        persist()
    }

    public func dismissFileError() {
        fileError = nil
    }

    private func takeDiskText(_ text: String, at index: Int) {
        guard Self.differs(notes[index].body, text) else { return }
        notes[index].body = text
        notes[index].modifiedAt = Date()
        _ = bumpRevision(notes[index].id)
    }

    /// The user's Trash, and the per-user Trash folder macOS keeps on every external volume.
    nonisolated public static func isInTrash(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// Returns the note's new revision, or nil when nothing changed.
    @discardableResult
    public func updateBody(_ id: Note.ID, _ body: String) -> Int? {
        guard let index = self.index(of: id),
              !notes[index].isLocked, Self.differs(notes[index].body, body) else { return nil }
        notes[index].body = body
        notes[index].modifiedAt = Date()
        if notes[index].localFile != nil {
            notes[index].localFile?.needsSave = true
        }
        persistSoon()
        return bumpRevision(id)
    }

    public func setLocked(_ id: Note.ID, _ locked: Bool) {
        guard let index = self.index(of: id) else { return }
        notes[index].isLocked = locked
        persist()
    }

    /// Names a note kept in the app by hand; an empty name goes back to its first line.
    public func rename(_ id: Note.ID, to title: String) {
        guard let index = self.index(of: id), !notes[index].isLocked, notes[index].localFile == nil else { return }
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(NoteNaming.maxTitleLength))
        let customTitle = trimmed.isEmpty ? nil : trimmed
        guard notes[index].customTitle != customTitle else { return }
        notes[index].customTitle = customTitle
        persist()
    }

    public var emptyNotes: [Note] {
        appNotes.filter { !$0.isLocked && $0.body.allSatisfy(\.isWhitespace) }
    }

    public var hasEmptyNotes: Bool {
        notes.contains { $0.localFile == nil && !$0.isLocked && $0.body.allSatisfy(\.isWhitespace) }
    }

    public func deleteEmptyNotes() {
        let empty = Set(emptyNotes.map(\.id))
        guard !empty.isEmpty else { return }
        notes.removeAll { empty.contains($0.id) }
        persist()
    }

    /// Removes a note kept in the app; files opened from disk are closed instead.
    public func delete(_ id: Note.ID) {
        guard let index = self.index(of: id), !notes[index].isLocked, notes[index].localFile == nil else { return }
        notes.remove(at: index)
        persist()
    }

    /// Takes an opened file off the list after writing its pending edits; the file stays on disk.
    public func close(_ id: Note.ID) {
        guard let index = self.index(of: id), notes[index].localFile != nil else { return }
        flushFileWrites()
        guard notes[index].localFile?.needsSave != true else {
            fileError = fileError ?? "“\(notes[index].title)” could not be saved to its file, so it is still open. Fix the save error, then close it again."
            return
        }
        notes.remove(at: index)
        persist()
    }

    /// Writes whatever changed, and waits for it; returns why the notes could not be saved, if they could not.
    @discardableResult
    public func saveNow() -> String? {
        flushFileWrites()
        saveCache()
        return notesFile.flush().map { "Couldn’t save your notes: \($0.localizedDescription)" }
    }

    /// Opened files whose edits have not reached the file yet; their text is still kept with the notes.
    public var unsavedFileNames: [String] {
        notes.filter { $0.localFile?.needsSave == true || fileConflict?.id == $0.id }.map(\.title)
    }

    private func writePendingFiles() {
        for note in notes where !writing.contains(note.id) && note.localFile?.needsSave == true && fileConflict?.id != note.id {
            guard let job = fileJob(note.id) else { continue }
            let body = note.body
            writing.insert(note.id)
            diskQueue.async { [finishedWrites, weak self] in
                finishedWrites.add(LocalFileDisk.write(job, body: body))
                Task { @MainActor in self?.applyFinishedWrites() }
            }
        }
    }

    private func applyFinishedWrites() {
        let before = changeCount
        for write in finishedWrites.take() {
            let id = write.job.id
            writing.remove(id)
            guard let index = self.index(of: id), notes[index].localFile != nil else { continue }
            if let moved = write.location?.moved {
                notes[index].localFile?.path = moved.path
                notes[index].localFile?.bookmark = moved.bookmark
            }
            let name = notes[index].title
            switch write.result {
            case .written(let stamp):
                notes[index].localFile?.stamp = stamp
                // Edits made while it was written still wait for the next write.
                if revision(of: id) == write.job.revision { notes[index].localFile?.needsSave = false }
                failedFileWrites.remove(id)
            case .changedOnDisk:
                fileConflict = FileConflict(id: id, name: name)
            case .missing:
                reportWriteFailure(id, "Could not save “\(name)”: the file is no longer at \(write.job.file.path) (it was deleted or moved to the Trash). Your text is still in the app.")
            case .failed(let message):
                reportWriteFailure(id, "Could not save “\(name)”: \(message) Your text is still in the app, and saving is retried on your next edit.")
            }
        }
        if changeCount != before { persistSoon() }
    }

    private func waitForFileWrites() {
        diskQueue.sync {}
        applyFinishedWrites()
    }

    /// Closing a file and quitting wait here until the latest text of every opened file has been written.
    private func flushFileWrites() {
        waitForFileWrites()
        writePendingFiles()
        waitForFileWrites()
    }

    private func reportWriteFailure(_ id: Note.ID, _ message: String) {
        guard !failedFileWrites.contains(id) else { return }
        failedFileWrites.insert(id)
        fileError = message
    }

    private func persist() {
        writePendingFiles()
        saveCache()
    }

    private func saveCache() {
        cacheTask?.cancel()
        guard savedCount != changeCount else { return }
        savedCount = changeCount
        notesFile.save(NotesSnapshot(notes: notes)) { [weak self] error in
            self?.savedCount = nil
            self?.fileError = "Couldn’t save your notes: \(error.localizedDescription) They are still open in the app."
        }
    }

    private func persistSoon() {
        cacheTask?.cancel()
        cacheTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.persist()
        }
    }
}
