import Foundation
import Synchronization

/// An opened file as the store knew it, handed to work that runs off the main thread.
struct FileJob: Sendable {
    let id: UUID
    let revision: Int
    let file: LocalFile
}

/// Reading and writing opened files. Nothing here touches the store, so it runs on the store's disk queue.
enum LocalFileDisk {
    static let maxFileSize = 5_000_000

    struct Location: Sendable {
        let url: URL
        /// Set when the bookmark found the file under a new name or in a new folder.
        let moved: LocalFile?
    }

    struct Check: Sendable {
        let job: FileJob
        let location: Location?
        let stamp: FileStamp?
        /// Read only when the file changed and the note has no edits of its own waiting.
        let disk: (text: String, encoding: UInt)?
    }

    enum WriteResult: Sendable {
        case written(FileStamp?)
        case changedOnDisk
        case missing
        case failed(String)
    }

    struct Write: Sendable {
        let job: FileJob
        let location: Location?
        let result: WriteResult
    }

    /*
     The stored path is tried first: resolving a bookmark costs far more, and is only needed once the file has
     moved. A file in the Trash counts as gone, so edits are not written there.
     */
    static func locate(_ file: LocalFile) -> Location? {
        if !NoteStore.isInTrash(file.path), FileManager.default.fileExists(atPath: file.path) {
            return Location(url: URL(fileURLWithPath: file.path), moved: nil)
        }
        var isStale = false
        guard let bookmark = file.bookmark,
              let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale) else { return nil }
        let url = resolved.standardizedFileURL
        guard !NoteStore.isInTrash(url.path), FileManager.default.fileExists(atPath: url.path) else { return nil }
        var moved = file
        moved.path = url.path
        moved.bookmark = (try? url.bookmarkData()) ?? file.bookmark
        return Location(url: url, moved: moved)
    }

    static func check(_ job: FileJob) -> Check {
        guard let location = locate(job.file) else { return Check(job: job, location: nil, stamp: nil, disk: nil) }
        let stamp = stamp(location.url)
        guard stamp != job.file.stamp, !job.file.needsSave, let (text, encoding) = try? readText(location.url) else {
            return Check(job: job, location: location, stamp: stamp, disk: nil)
        }
        return Check(job: job, location: location, stamp: stamp, disk: (text, encoding.rawValue))
    }

    // A file another app changed since the note last read or wrote it is left alone, so its version is never lost.
    static func write(_ job: FileJob, body: String) -> Write {
        guard let location = locate(job.file) else { return Write(job: job, location: nil, result: .missing) }
        guard stamp(location.url) == job.file.stamp else { return Write(job: job, location: location, result: .changedOnDisk) }
        do {
            try write(body, encoding: job.file.encoding, to: location.url)
            return Write(job: job, location: location, result: .written(stamp(location.url)))
        } catch {
            return Write(job: job, location: location, result: .failed(error.localizedDescription))
        }
    }

    static func stamp(_ url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
        return FileStamp(modifiedAt: values.contentModificationDate, size: values.fileSize)
    }

    static func readText(_ url: URL) throws -> (String, String.Encoding) {
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
}

/// Writes finished on the disk queue, waiting for the main thread to apply them.
final class FileWriteInbox: Sendable {
    private let writes = Mutex<[LocalFileDisk.Write]>([])

    func add(_ write: LocalFileDisk.Write) {
        writes.withLock { $0.append(write) }
    }

    func take() -> [LocalFileDisk.Write] {
        writes.withLock { writes in
            defer { writes = [] }
            return writes
        }
    }
}
