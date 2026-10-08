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
    public private(set) var notes: [Note] = []
    public private(set) var fileConflict: FileConflict?
    public private(set) var fileError: String?

    @ObservationIgnored private let cache: NoteCache
    @ObservationIgnored private var cacheTask: Task<Void, Never>?
    @ObservationIgnored private var failedFileWrites: Set<Note.ID> = []
    @ObservationIgnored private var keepsUnreadableFile = false
    private static let maxFileSize = 5_000_000

    public init(cache: NoteCache) {
        self.cache = cache
        let snapshot = cache.load()
        // Caches from before manual ordering kept notes in creation order and showed them newest first.
        notes = snapshot.isOrdered ? snapshot.notes : snapshot.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        if let copy = snapshot.unreadableCopy {
            fileError = "Your notes file could not be read, so the list starts empty. The unreadable file was kept at \(copy.path)."
        }
        if snapshot.isUnreadableInPlace {
            keepsUnreadableFile = true
            fileError = "Your notes file at \(cache.url.path) could not be read, so the list starts empty. Nothing will be saved over it until the app is restarted and the file can be read."
        }
        refreshLocalFiles()
    }

    public func note(_ id: Note.ID) -> Note? {
        notes.first { $0.id == id }
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

    public func pinnedFirst(_ notes: [Note]) -> [Note] {
        notes.filter(\.isPinned) + notes.filter { !$0.isPinned }
    }

    public func setPinned(_ id: Note.ID, _ pinned: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].isPinned != pinned else { return }
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
        if let index = notes.firstIndex(where: { $0.localFile?.path == url.path }) {
            syncWithDisk(index)
            persist()
            return notes[index].id
        }
        let (text, encoding) = try Self.readText(url)
        let file = LocalFile(path: url.path, bookmark: try? url.bookmarkData(), stamp: Self.stamp(url), encoding: encoding.rawValue)
        let note = Note(body: text, modifiedAt: Date(), localFile: file)
        notes.insert(note, at: min(max(position, 0), notes.count))
        persist()
        return note.id
    }

    public func refreshLocalFiles() {
        for index in notes.indices where notes[index].localFile != nil {
            syncWithDisk(index)
        }
    }

    public func resolveFileConflict(keepAppVersion: Bool) {
        guard let conflict = fileConflict else { return }
        fileConflict = nil
        guard let index = notes.firstIndex(where: { $0.id == conflict.id }), let url = resolvedURL(index) else { return }
        if keepAppVersion {
            notes[index].localFile?.stamp = Self.stamp(url)
            notes[index].localFile?.needsSave = true
        } else if let (text, encoding) = try? Self.readText(url) {
            takeDiskText(text, at: index)
            notes[index].localFile?.encoding = encoding.rawValue
            notes[index].localFile?.stamp = Self.stamp(url)
            notes[index].localFile?.needsSave = false
        }
        persist()
    }

    public func dismissFileError() {
        fileError = nil
    }

    private func syncWithDisk(_ index: Int) {
        guard let file = notes[index].localFile, let url = resolvedURL(index) else { return }
        let stamp = Self.stamp(url)
        guard stamp != file.stamp else { return }
        if file.needsSave {
            fileConflict = FileConflict(id: notes[index].id, name: notes[index].title)
        } else if let (text, encoding) = try? Self.readText(url) {
            takeDiskText(text, at: index)
            notes[index].localFile?.encoding = encoding.rawValue
            notes[index].localFile?.stamp = stamp
        }
    }

    private func takeDiskText(_ text: String, at index: Int) {
        guard notes[index].body != text else { return }
        notes[index].body = text
        notes[index].modifiedAt = Date()
    }

    // Bookmarks follow a file that was renamed or moved; a file in the Trash counts as gone so edits are not written there.
    private func resolvedURL(_ index: Int) -> URL? {
        guard let file = notes[index].localFile else { return nil }
        var url = URL(fileURLWithPath: file.path)
        var isStale = false
        if let bookmark = file.bookmark,
           let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale) {
            url = resolved.standardizedFileURL
        }
        guard !url.path.contains("/.Trash/"), FileManager.default.fileExists(atPath: url.path) else { return nil }
        if url.path != file.path || isStale {
            notes[index].localFile?.path = url.path
            notes[index].localFile?.bookmark = (try? url.bookmarkData()) ?? file.bookmark
        }
        return url
    }

    private static func stamp(_ url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
        return FileStamp(modifiedAt: values.contentModificationDate, size: values.fileSize)
    }

    private static func readText(_ url: URL) throws -> (String, String.Encoding) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true else { throw FileOpenError.notText(url.lastPathComponent) }
        guard (values?.fileSize ?? 0) <= maxFileSize else { throw FileOpenError.tooLarge(url.lastPathComponent) }
        var encoding = String.Encoding.utf8
        do {
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            return (text, encoding)
        } catch {
            throw FileOpenError.notText(url.lastPathComponent)
        }
    }

    // Replacing the file keeps its Finder tags, extended attributes and creation date; an in-place write covers folders where that fails.
    private static func write(_ text: String, encoding: UInt, to url: URL) throws {
        let preferred = String.Encoding(rawValue: encoding)
        guard let data = text.data(using: text.canBeConverted(to: preferred) ? preferred : .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let manager = FileManager.default
        if let folder = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true) {
            defer { try? manager.removeItem(at: folder) }
            let temporary = folder.appendingPathComponent(url.lastPathComponent)
            if (try? data.write(to: temporary)) != nil, (try? manager.replaceItemAt(url, withItemAt: temporary)) != nil {
                return
            }
        }
        try data.write(to: url)
    }

    public func updateBody(_ id: Note.ID, _ body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              !notes[index].isLocked, notes[index].body != body else { return }
        notes[index].body = body
        notes[index].modifiedAt = Date()
        if notes[index].localFile != nil {
            notes[index].localFile?.needsSave = true
        }
        persistSoon()
    }

    public func setLocked(_ id: Note.ID, _ locked: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isLocked = locked
        persist()
    }

    /// Names a note kept in the app by hand; an empty name goes back to its first line.
    public func rename(_ id: Note.ID, to title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), !notes[index].isLocked, notes[index].localFile == nil else { return }
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(NoteNaming.maxTitleLength))
        let customTitle = trimmed.isEmpty ? nil : trimmed
        guard notes[index].customTitle != customTitle else { return }
        notes[index].customTitle = customTitle
        persist()
    }

    /// Notes kept in the app with no text at all, which the list shows as "Untitled".
    public var emptyNotes: [Note] {
        appNotes.filter { !$0.isLocked && $0.body.allSatisfy(\.isWhitespace) }
    }

    public func deleteEmptyNotes() {
        let empty = Set(emptyNotes.map(\.id))
        guard !empty.isEmpty else { return }
        notes.removeAll { empty.contains($0.id) }
        persist()
    }

    /// Removes a note kept in the app; files opened from disk are closed instead.
    public func delete(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), !notes[index].isLocked, notes[index].localFile == nil else { return }
        notes.remove(at: index)
        persist()
    }

    /// Takes an opened file off the list after writing its pending edits; the file stays on disk.
    public func close(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].localFile != nil else { return }
        writePendingFiles()
        guard notes[index].localFile?.needsSave != true else {
            fileError = fileError ?? "“\(notes[index].title)” could not be saved to its file, so it is still open. Fix the save error, then close it again."
            return
        }
        notes.remove(at: index)
        persist()
    }

    /// Writes everything now; returns why the notes could not be saved, if they could not.
    @discardableResult
    public func saveNow() -> String? {
        persist()
        return cache.flush().map { "Couldn’t save your notes: \($0.localizedDescription)" }
    }

    private func writePendingFiles() {
        for index in notes.indices {
            guard let file = notes[index].localFile, file.needsSave, fileConflict?.id != notes[index].id else { continue }
            let id = notes[index].id
            let name = notes[index].title
            guard let url = resolvedURL(index) else {
                reportWriteFailure(id, "Could not save “\(name)”: the file is no longer at \(file.path) (it was deleted or moved to the Trash). Your text is still in the app.")
                continue
            }
            guard Self.stamp(url) == file.stamp else {
                fileConflict = FileConflict(id: id, name: name)
                continue
            }
            do {
                try Self.write(notes[index].body, encoding: file.encoding, to: url)
                notes[index].localFile?.needsSave = false
                notes[index].localFile?.stamp = Self.stamp(url)
                failedFileWrites.remove(id)
            } catch {
                reportWriteFailure(id, "Could not save “\(name)”: \(error.localizedDescription) Your text is still in the app, and saving is retried on your next edit.")
            }
        }
    }

    private func reportWriteFailure(_ id: Note.ID, _ message: String) {
        guard !failedFileWrites.contains(id) else { return }
        failedFileWrites.insert(id)
        fileError = message
    }

    private func persist() {
        writePendingFiles()
        cacheTask?.cancel()
        guard !keepsUnreadableFile else { return }
        cache.save(CacheSnapshot(notes: notes)) { [weak self] error in
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
