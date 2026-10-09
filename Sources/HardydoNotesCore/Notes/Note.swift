import Foundation

public struct Note: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var body: String {
        didSet { refreshSummary() }
    }
    public var modifiedAt: Date
    public var isLocked: Bool
    public var localFile: LocalFile? {
        didSet { if oldValue?.path != localFile?.path { refreshSummary() } }
    }
    /// Pinned notes stay at the top of their group.
    public var isPinned: Bool
    /// A name given by hand to a note kept in the app, in place of its first line.
    public var customTitle: String? {
        didSet { refreshSummary() }
    }
    // Kept with the body so lists read them without scanning the text on every redraw.
    public private(set) var title = ""
    public private(set) var snippet = ""

    public init(
        id: UUID = UUID(),
        body: String = "",
        modifiedAt: Date = Date(),
        isLocked: Bool = false,
        localFile: LocalFile? = nil,
        isPinned: Bool = false,
        customTitle: String? = nil
    ) {
        self.id = id
        self.body = body
        self.modifiedAt = modifiedAt
        self.isLocked = isLocked
        self.localFile = localFile
        self.isPinned = isPinned
        self.customTitle = customTitle
        refreshSummary()
    }

    private enum CodingKeys: String, CodingKey {
        case id, body, modifiedAt, isLocked, localFile, isPinned, customTitle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        localFile = try container.decodeIfPresent(LocalFile.self, forKey: .localFile)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        refreshSummary()
    }

    public var fileName: String {
        localFile?.name ?? NoteNaming.fileName(forTitle: title)
    }

    private mutating func refreshSummary() {
        let summary = NoteNaming.summary(of: body)
        if let localFile {
            title = localFile.name
            snippet = summary.firstLine
        } else if let customTitle {
            title = customTitle
            snippet = summary.firstLine
        } else {
            title = summary.title ?? NoteNaming.untitled
            snippet = summary.afterTitle
        }
    }

    public var language: ContentLanguage {
        ContentLanguage.detect(body, fileName: localFile?.name)
    }
}

/// What lists show for a note, without its text, so comparing rows never scans a long body.
public struct NoteSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let snippet: String
    public let modifiedAt: Date
    public let isPinned: Bool
    public let isLocked: Bool
    public let filePath: String?
}

extension Note {
    public var summary: NoteSummary {
        NoteSummary(id: id, title: title, snippet: snippet, modifiedAt: modifiedAt, isPinned: isPinned, isLocked: isLocked, filePath: localFile?.path)
    }
}

/*
 A note's text with the revision it belongs to. SwiftUI compares view inputs with ==, so equality looks only at
 the note and the revision; comparing the text itself scanned megabytes after every pause in typing.
 */
public struct NoteText: Equatable, Sendable {
    public let note: Note.ID
    public let revision: Int
    public let string: String

    public init(note: Note.ID, revision: Int, string: String) {
        self.note = note
        self.revision = revision
        self.string = string
    }

    public static func == (lhs: NoteText, rhs: NoteText) -> Bool {
        lhs.note == rhs.note && lhs.revision == rhs.revision
    }
}

public struct FileStamp: Codable, Equatable, Sendable {
    public var modifiedAt: Date?
    public var size: Int?

    public init(modifiedAt: Date?, size: Int?) {
        self.modifiedAt = modifiedAt
        self.size = size
    }
}

public struct LocalFile: Codable, Equatable, Sendable {
    public var path: String
    public var bookmark: Data?
    public var stamp: FileStamp?
    public var encoding: UInt
    public var needsSave: Bool

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }

    public init(path: String, bookmark: Data? = nil, stamp: FileStamp? = nil, encoding: UInt = String.Encoding.utf8.rawValue, needsSave: Bool = false) {
        self.path = path
        self.bookmark = bookmark
        self.stamp = stamp
        self.encoding = encoding
        self.needsSave = needsSave
    }
}

public enum NoteNaming {
    public static let untitled = "Untitled"
    static let maxTitleLength = 80

    /// Lines of only punctuation, such as a JSON note's opening brace, do not make a title.
    static func isTitleLine(_ line: Substring) -> Bool {
        line.contains { $0.isLetter || $0.isNumber }
    }

    public static func title(for body: String) -> String {
        summary(of: body).title ?? untitled
    }

    /// The title line and the first lines with text before and after it, read only as far as needed.
    static func summary(of body: String) -> (title: String?, firstLine: String, afterTitle: String) {
        var title: String?
        var firstLine: String?
        var afterTitle: String?
        body.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            if firstLine == nil { firstLine = snippetText(trimmed) }
            if title == nil {
                if isTitleLine(Substring(line)) { title = titleText(trimmed) }
            } else {
                afterTitle = snippetText(trimmed)
            }
            stop = title != nil && afterTitle != nil
        }
        return (title, firstLine ?? "", afterTitle ?? "")
    }

    private static func titleText(_ line: String) -> String {
        String(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).prefix(maxTitleLength))
    }

    /// Heading marks are dropped from a snippet, but not a hashtag such as "#todo".
    private static func snippetText(_ line: String) -> String {
        let marks = line.prefix { $0 == "#" }
        let rest = line.dropFirst(marks.count)
        return (marks.isEmpty || rest.first?.isWhitespace == true || rest.isEmpty ? rest : Substring(line)).trimmingCharacters(in: .whitespaces)
    }

    public static func fileName(for body: String) -> String {
        fileName(forTitle: title(for: body))
    }

    public static func fileName(forTitle title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = title.unicodeScalars
            .map { forbidden.contains($0) ? "-" : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return (cleaned.isEmpty ? untitled : cleaned) + ".md"
    }
}
