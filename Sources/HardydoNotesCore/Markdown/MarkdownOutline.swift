import Foundation

public struct MarkdownHeading: Equatable, Sendable {
    public let line: Int
    public let level: Int
    public let title: String

    public init(line: Int, level: Int, title: String) {
        self.line = line
        self.level = level
        self.title = title
    }
}

/// The headings of a note, found by the same block scan that folds them, so the breadcrumb and the folds agree.
public enum MarkdownOutline {
    /// Markdown headings outside code fences and tables, in document order.
    public static func headings(in text: String) -> [MarkdownHeading] {
        let lines = CodeFolding.Lines(text: text as NSString)
        return CodeFolding.markdownBlocks(lines, (0..<lines.count).map(lines.content)).headings
    }

    /// The headings that enclose `line`, outermost first, the way VS Code's breadcrumbs nest document symbols.
    public static func path(_ headings: [MarkdownHeading], toLine line: Int) -> [MarkdownHeading] {
        var path: [MarkdownHeading] = []
        for heading in headings {
            guard heading.line <= line else { break }
            while let last = path.last, last.level >= heading.level { path.removeLast() }
            path.append(heading)
        }
        return path
    }
}
