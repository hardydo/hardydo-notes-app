import Foundation

public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
}

public enum LinePrefix: Equatable, Sendable {
    case heading(Int)
    case bullet
    case numbered
    case task
    case quote
}

public enum MarkdownFormatting {
    public static func toggleWrap(_ text: String, selection: NSRange, marker: String) -> TextEdit {
        let ns = text as NSString
        let m = (marker as NSString).length
        let selected = ns.substring(with: selection)
        let selectedNS = selected as NSString

        let char = (marker as NSString).character(at: 0)

        func run(in string: NSString, from start: Int, step: Int) -> Int {
            var count = 0
            var index = start
            while index >= 0, index < string.length, string.character(at: index) == char {
                count += 1
                index += step
            }
            return count
        }

        // "*" shares its character with "**", so italic is present only on odd runs ("*x*", "***x***").
        func carriesMarker(_ run: Int) -> Bool {
            marker == "*" ? run % 2 == 1 : run >= m
        }

        if selection.length >= 2 * m,
           carriesMarker(run(in: selectedNS, from: 0, step: 1)),
           carriesMarker(run(in: selectedNS, from: selectedNS.length - 1, step: -1)) {
            let inner = selectedNS.substring(with: NSRange(location: m, length: selectedNS.length - 2 * m))
            return TextEdit(
                range: selection,
                replacement: inner,
                selection: NSRange(location: selection.location, length: (inner as NSString).length)
            )
        }

        let before = NSRange(location: selection.location - m, length: m)
        let after = NSRange(location: NSMaxRange(selection), length: m)
        if before.location >= 0, NSMaxRange(after) <= ns.length,
           carriesMarker(run(in: ns, from: selection.location - 1, step: -1)),
           carriesMarker(run(in: ns, from: NSMaxRange(selection), step: 1)) {
            return TextEdit(
                range: NSRange(location: before.location, length: selection.length + 2 * m),
                replacement: selected,
                selection: NSRange(location: before.location, length: selection.length)
            )
        }

        return TextEdit(
            range: selection,
            replacement: marker + selected + marker,
            selection: NSRange(location: selection.location + m, length: selection.length)
        )
    }

    public static func insertLink(_ text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let label = ns.substring(with: selection)
        let url = "https://"
        let replacement = "[\(label)](\(url))"
        let selectionAfter = label.isEmpty
            ? NSRange(location: selection.location + 1, length: 0)
            : NSRange(location: selection.location + (label as NSString).length + 3, length: (url as NSString).length)
        return TextEdit(range: selection, replacement: replacement, selection: selectionAfter)
    }

    /// The first header cell of a new table, selected so typing names the column.
    public static let tableFirstCell = NSRange(location: 2, length: ("Column 1" as NSString).length)

    /// A table with a header row naming each column and `rows` empty rows below it.
    public static func table(rows: Int, columns: Int) -> String {
        let columns = max(1, columns)
        let line = { (cells: [String]) in "| " + cells.joined(separator: " | ") + " |" }
        let header = line((1...columns).map { "Column \($0)" })
        let divider = line(Array(repeating: "---", count: columns))
        let body = Array(repeating: line(Array(repeating: "", count: columns)), count: max(0, rows))
        return ([header, divider] + body).joined(separator: "\n")
    }

    public static let rule = "---"

    /// Puts a block such as a table on its own lines below the caret's line, with a blank line around it so Markdown reads it as a block.
    public static func insertBlock(_ text: String, selection: NSRange, block: String, select: NSRange? = nil) -> TextEdit {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: NSMaxRange(selection), length: 0))
        var contentEnd = NSMaxRange(line)
        while contentEnd > line.location, let scalar = UnicodeScalar(ns.character(at: contentEnd - 1)), CharacterSet.newlines.contains(scalar) {
            contentEnd -= 1
        }
        let content = NSRange(location: line.location, length: contentEnd - line.location)
        let hasLineBreak = contentEnd < NSMaxRange(line)
        func isBlank(_ range: NSRange) -> Bool {
            ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let nextLineIsText = hasLineBreak && NSMaxRange(line) < ns.length && !isBlank(ns.lineRange(for: NSRange(location: NSMaxRange(line), length: 0)))

        let range: NSRange
        let prefix: String
        if isBlank(content) {
            range = content
            let previousIsText = line.location > 0 && !isBlank(ns.lineRange(for: NSRange(location: line.location - 1, length: 0)))
            prefix = previousIsText ? "\n" : ""
        } else {
            range = NSRange(location: contentEnd, length: 0)
            prefix = "\n\n"
        }
        let suffix = !hasLineBreak || nextLineIsText ? "\n" : ""
        let replacement = prefix + block + suffix
        let blockStart = range.location + (prefix as NSString).length
        let selectionAfter = select.map { NSRange(location: blockStart + $0.location, length: $0.length) }
            ?? NSRange(location: min(blockStart + (block as NSString).length + 1, ns.length - range.length + (replacement as NSString).length), length: 0)
        return TextEdit(range: range, replacement: replacement, selection: selectionAfter)
    }

    private static let existingPrefix = regex(
        #"^(#{1,6}[ \t]+|>[ \t]?|[ \t]*[-*+][ \t]+\[[ xX]\][ \t]+|[ \t]*[-*+][ \t]+|[ \t]*\d+[.)][ \t]+)"#
    )

    private static func split(_ line: String) -> (prefix: String, content: String) {
        let ns = line as NSString
        guard let match = existingPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return ("", line)
        }
        return (ns.substring(with: match.range), ns.substring(from: NSMaxRange(match.range)))
    }

    private static func kind(of prefix: String) -> LinePrefix? {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("#") { return .heading(trimmed.count) }
        if trimmed.hasPrefix(">") { return .quote }
        if trimmed.hasSuffix("]") { return .task }
        if trimmed.first?.isNumber == true { return .numbered }
        return .bullet
    }

    private static func render(_ prefix: LinePrefix, index: Int) -> String {
        switch prefix {
        case .heading(let level): String(repeating: "#", count: level) + " "
        case .bullet: "- "
        case .numbered: "\(index + 1). "
        case .task: "- [ ] "
        case .quote: "> "
        }
    }

    public static func toggleLinePrefix(_ text: String, selection: NSRange, prefix: LinePrefix) -> TextEdit {
        let ns = text as NSString
        var block = ns.lineRange(for: selection)
        if block.length > 0, ns.substring(with: NSRange(location: NSMaxRange(block) - 1, length: 1)) == "\n" {
            block.length -= 1
        }
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let parts = lines.map(split)
        let nonEmpty = parts.filter { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty || !$0.prefix.isEmpty }
        let removing = !nonEmpty.isEmpty && nonEmpty.allSatisfy { kind(of: $0.prefix) == prefix }

        var index = 0
        var firstLineDelta = 0
        let newLines = parts.enumerated().map { offset, part -> String in
            let isBlank = part.prefix.isEmpty && part.content.trimmingCharacters(in: .whitespaces).isEmpty
            let newPrefix: String
            if removing || (isBlank && lines.count > 1) {
                newPrefix = ""
            } else {
                newPrefix = render(prefix, index: index)
                index += 1
            }
            if offset == 0 {
                firstLineDelta = (newPrefix as NSString).length - (part.prefix as NSString).length
            }
            return newPrefix + part.content
        }
        let replacement = newLines.joined(separator: "\n")
        let totalDelta = (replacement as NSString).length - block.length

        let location = max(block.location, selection.location + firstLineDelta)
        let end = max(location, NSMaxRange(selection) + totalDelta)
        return TextEdit(range: block, replacement: replacement, selection: NSRange(location: location, length: end - location))
    }
}
