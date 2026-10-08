import Foundation

public struct CacheSnapshot: Codable, Equatable, Sendable {
    public var notes: [Note] = []
    public var isOrdered = true
    /// Set when the file could not be read and was copied aside instead.
    public var unreadableCopy: URL?
    /// Set when the file could not be read and not copied either, so saving over it would lose it.
    public var isUnreadableInPlace = false

    public init(notes: [Note] = []) {
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case notes, isOrdered
    }

    public static func == (lhs: CacheSnapshot, rhs: CacheSnapshot) -> Bool {
        lhs.notes == rhs.notes && lhs.isOrdered == rhs.isOrdered
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decode([Note].self, forKey: .notes)
        isOrdered = try container.decodeIfPresent(Bool.self, forKey: .isOrdered) ?? false
    }
}

// One queue for every write, so saves land in order and a load sees the last one queued before it.
private let diskQueue = DispatchQueue(label: "com.hardydo.notes.disk", qos: .utility)
// Only touched on diskQueue.
nonisolated(unsafe) private var writeErrors: [URL: any Error] = [:]

public struct NoteCache: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var standard: NoteCache {
        NoteCache(url: AppPaths.notesFile)
    }

    public func load() -> CacheSnapshot {
        diskQueue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return CacheSnapshot() }
            if let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(CacheSnapshot.self, from: data) {
                return snapshot
            }
            // Keep the unreadable file so the next save cannot silently wipe the user's notes.
            let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            var snapshot = CacheSnapshot()
            if (try? FileManager.default.copyItem(at: url, to: backup)) != nil {
                snapshot.unreadableCopy = backup
            } else {
                snapshot.isUnreadableInPlace = true
            }
            return snapshot
        }
    }

    /// Encodes and writes off the main thread; `flush` waits for it. A failure is reported on the main actor.
    public func save(_ snapshot: CacheSnapshot, onFailure: @escaping @MainActor @Sendable (Error) -> Void = { _ in }) {
        let url = url
        diskQueue.async {
            do {
                try writeJSON(snapshot, to: url)
            } catch {
                Task { @MainActor in onFailure(error) }
            }
        }
    }

    /// Waits for queued writes; returns the error of the last one if it failed.
    @discardableResult
    public func flush() -> (any Error)? {
        diskQueue.sync { writeErrors[url] }
    }
}

/// A small JSON document saved next to the notes, such as the sidebar groups.
public struct JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        diskQueue.sync {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
        }
    }

    public func save(_ value: Value) {
        let url = url
        diskQueue.async { try? writeJSON(value, to: url) }
    }

    @discardableResult
    public func flush() -> (any Error)? {
        diskQueue.sync { writeErrors[url] }
    }
}

private func writeJSON(_ value: some Encodable, to url: URL) throws {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic])
        writeErrors[url] = nil
    } catch {
        writeErrors[url] = error
        throw error
    }
}
