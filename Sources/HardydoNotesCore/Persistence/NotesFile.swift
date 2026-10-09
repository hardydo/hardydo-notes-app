import Foundation

public struct NotesSnapshot: Codable, Equatable, Sendable {
    public var notes: [Note] = []
    public var isOrdered = true
    /// Set when the file could not be read and was copied aside instead.
    public var unreadableCopy: URL?
    /// Set when the file could not be read and not copied either, so saving over it would lose it.
    public var isUnreadableInPlace = false
    /// Set when the notes came from the copy kept by the save before the last one.
    public var recoveredFromPrevious = false
    public var skippedNotes = 0

    public init(notes: [Note] = []) {
        self.notes = notes
    }

    public var loadedCleanly: Bool {
        unreadableCopy == nil && !isUnreadableInPlace && !recoveredFromPrevious && skippedNotes == 0
    }

    private enum CodingKeys: String, CodingKey {
        case notes, isOrdered
    }

    public static func == (lhs: NotesSnapshot, rhs: NotesSnapshot) -> Bool {
        lhs.notes == rhs.notes && lhs.isOrdered == rhs.isOrdered
    }

    // One damaged note is skipped rather than hiding all the others.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([Lossy<Note>].self, forKey: .notes)
        notes = entries.compactMap(\.value)
        skippedNotes = entries.count - notes.count
        isOrdered = try container.decodeIfPresent(Bool.self, forKey: .isOrdered) ?? false
    }
}

private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// One queue for every write, so saves land in order and a load sees the last one queued before it.
private let diskQueue = DispatchQueue(label: "com.hardydo.notes.disk", qos: .utility)
// Only touched on diskQueue.
nonisolated(unsafe) private var writeErrors: [URL: any Error] = [:]

public struct NotesFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> NotesSnapshot {
        diskQueue.sync {
            let read = readJSON(NotesSnapshot.self, at: url)
            var snapshot = read.value ?? NotesSnapshot()
            snapshot.recoveredFromPrevious = read.fromPrevious
            snapshot.unreadableCopy = read.unreadableCopy
            snapshot.isUnreadableInPlace = read.isUnreadableInPlace
            if snapshot.skippedNotes > 0, !read.fromPrevious {
                if let copy = copyAside(url) { snapshot.unreadableCopy = copy } else { snapshot.isUnreadableInPlace = true }
            }
            return snapshot
        }
    }

    /// Encodes and writes off the main thread; `flush` waits for it. A failure is reported on the main actor.
    public func save(_ snapshot: NotesSnapshot, onFailure: @escaping @MainActor @Sendable (Error) -> Void = { _ in }) {
        enqueueWrite(snapshot, to: url, onFailure: onFailure)
    }

    /// Waits for queued writes; returns the error of the last one if it failed.
    @discardableResult
    public func flush() -> (any Error)? {
        diskQueue.sync { writeErrors[url] }
    }

    /// The copy each save keeps of the file it replaces, read when the current file turns out damaged.
    public static func previousVersion(of url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("previous.json")
    }
}

/// A small JSON document saved next to the notes, such as the sidebar groups.
public struct JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The saved value, or the one before it when the file is damaged; `problem` says what happened then.
    public func load() -> (value: Value?, problem: String?) {
        diskQueue.sync {
            let read = readJSON(Value.self, at: url)
            let name = url.lastPathComponent
            if let copy = read.unreadableCopy {
                let outcome = read.fromPrevious ? "the version saved before it was restored" : "it starts empty"
                return (read.value, "\(name) could not be read, so \(outcome). The unreadable file was kept at \(copy.path).")
            }
            if read.isUnreadableInPlace {
                return (read.value, "\(name) could not be read or copied aside. Saving a change will replace it.")
            }
            return (read.value, nil)
        }
    }

    public func save(_ value: Value, onFailure: @escaping @MainActor @Sendable (Error) -> Void = { _ in }) {
        enqueueWrite(value, to: url, onFailure: onFailure)
    }

    @discardableResult
    public func flush() -> (any Error)? {
        diskQueue.sync { writeErrors[url] }
    }
}


private func enqueueWrite(_ value: some Encodable & Sendable, to url: URL, onFailure: @escaping @MainActor @Sendable (Error) -> Void) {
    diskQueue.async {
        do {
            try writeJSON(value, to: url)
        } catch {
            Task { @MainActor in onFailure(error) }
        }
    }
}

private func readJSON<Value: Decodable>(_ type: Value.Type, at url: URL) -> (value: Value?, fromPrevious: Bool, unreadableCopy: URL?, isUnreadableInPlace: Bool) {
    func decode(_ url: URL) -> Value? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
    let exists = FileManager.default.fileExists(atPath: url.path)
    if exists, let value = decode(url) { return (value, false, nil, false) }
    // Keep the unreadable file so the next save cannot silently wipe it.
    let copy = exists ? copyAside(url) : nil
    let previous = decode(NotesFile.previousVersion(of: url))
    return (previous, previous != nil, copy, exists && copy == nil)
}

private func copyAside(_ url: URL) -> URL? {
    let stamp = "unreadable-\(Int(Date().timeIntervalSince1970))"
    for attempt in 0..<100 {
        let backup = url.deletingPathExtension().appendingPathExtension(attempt == 0 ? "\(stamp).json" : "\(stamp)-\(attempt).json")
        guard !FileManager.default.fileExists(atPath: backup.path) else { continue }
        return (try? FileManager.default.copyItem(at: url, to: backup)) != nil ? backup : nil
    }
    return nil
}

/*
 The new file reaches the disk itself before it replaces the old one, which is kept as the previous version,
 so a power cut or a damaged write still leaves one good copy. Between the two renames only the previous
 version exists, and loading falls back to it.
 */
private func writeJSON(_ value: some Encodable, to url: URL) throws {
    let manager = FileManager.default
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    defer { try? manager.removeItem(at: temporary) }
    do {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
        try handle.close()
        if manager.fileExists(atPath: url.path) {
            try rename(url, to: NotesFile.previousVersion(of: url))
        }
        try rename(temporary, to: url)
        writeErrors[url] = nil
    } catch {
        writeErrors[url] = error
        throw error
    }
}

private func rename(_ source: URL, to destination: URL) throws {
    guard Darwin.rename(source.path, destination.path) == 0 else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
    }
}
