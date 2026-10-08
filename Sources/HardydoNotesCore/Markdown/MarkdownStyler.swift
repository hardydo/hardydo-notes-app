import Foundation

public enum MarkdownStyle: Equatable, Sendable {
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case quote
    case listMarker
    case taskDone
    case link
    case syntax
}

public struct MarkdownSpan: Equatable, Sendable {
    public let range: NSRange
    public let style: MarkdownStyle

    public init(_ range: NSRange, _ style: MarkdownStyle) {
        self.range = range
        self.style = style
    }
}

public enum MarkdownStyler {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let fence = regex(#"^```[^\n]*\n[\s\S]*?(?:^```[ \t]*$|\z)"#)
    private static let fenceLine = regex(#"^```[^\n]*$"#)
    private static let heading = regex(#"^(#{1,6})[ \t]+.*$"#)
    private static let quote = regex(#"^(>+)[ \t]?.*$"#)
    private static let task = regex(#"^[ \t]*[-*+][ \t]+\[([ xX])\][ \t]+(.*)$"#)
    private static let taskMarker = regex(#"^[ \t]*[-*+][ \t]+\[[ xX]\]"#)
    private static let bullet = regex(#"^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t]+)"#)
    private static let rule = regex(#"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    // Spans are capped so an unclosed marker on a long line cannot make each keystroke rescan the rest of the line.
    private static let bold = regex(#"(\*\*|__)(?=\S)(.{1,500}?)(?<=\S)\1"#)
    private static let italicStar = regex(#"(?<![*\w])\*(?=[^\s*])(.{1,500}?)(?<=[^\s*])\*(?!\*)"#)
    private static let italicUnderscore = regex(#"(?<![_\w])_(?=[^\s_])(.{1,500}?)(?<=[^\s_])_(?![_\w])"#)
    private static let strike = regex(#"~~(?=\S)(.{1,500}?)(?<=\S)~~"#)
    private static let link = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)

    public static func spans(in text: String) -> [MarkdownSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [MarkdownSpan] = []
        var protected: [NSRange] = []

        for match in fence.matches(in: text, range: full) {
            spans.append(MarkdownSpan(match.range, .codeBlock))
            for line in fenceLine.matches(in: text, range: match.range) {
                spans.append(MarkdownSpan(line.range, .syntax))
            }
            protected.append(match.range)
        }

        // Protected ranges never overlap and are kept sorted, so the last one starting before the range's end is the only candidate.
        func isFree(_ range: NSRange) -> Bool {
            var low = 0
            var high = protected.count
            while low < high {
                let mid = (low + high) / 2
                if protected[mid].location < NSMaxRange(range) { low = mid + 1 } else { high = mid }
            }
            return low == 0 || NSMaxRange(protected[low - 1]) <= range.location
        }

        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for match in re.matches(in: text, range: full) where isFree(match.range) {
                body(match)
            }
        }

        each(heading) { m in
            spans.append(MarkdownSpan(m.range, .heading(m.range(at: 1).length)))
            spans.append(MarkdownSpan(m.range(at: 1), .syntax))
        }
        each(quote) { m in
            spans.append(MarkdownSpan(m.range, .quote))
            spans.append(MarkdownSpan(m.range(at: 1), .syntax))
        }
        each(rule) { m in spans.append(MarkdownSpan(m.range, .syntax)) }
        each(task) { m in
            if ns.substring(with: m.range(at: 1)) != " " {
                spans.append(MarkdownSpan(m.range(at: 2), .taskDone))
            }
        }
        each(taskMarker) { m in spans.append(MarkdownSpan(m.range, .listMarker)) }
        each(bullet) { m in
            if rule.firstMatch(in: text, range: ns.lineRange(for: m.range)) == nil {
                spans.append(MarkdownSpan(m.range, .listMarker))
            }
        }

        var codeRanges: [NSRange] = []
        each(inlineCode) { m in
            spans.append(MarkdownSpan(m.range, .inlineCode))
            spans.append(MarkdownSpan(NSRange(location: m.range.location, length: 1), .syntax))
            spans.append(MarkdownSpan(NSRange(location: NSMaxRange(m.range) - 1, length: 1), .syntax))
            codeRanges.append(m.range)
        }
        protected = (protected + codeRanges).sorted { $0.location < $1.location }

        func wrapped(_ re: NSRegularExpression, markerLength: (NSTextCheckingResult) -> Int, style: MarkdownStyle) {
            each(re) { m in
                let marker = markerLength(m)
                spans.append(MarkdownSpan(m.range, style))
                spans.append(MarkdownSpan(NSRange(location: m.range.location, length: marker), .syntax))
                spans.append(MarkdownSpan(NSRange(location: NSMaxRange(m.range) - marker, length: marker), .syntax))
            }
        }
        wrapped(bold, markerLength: { _ in 2 }, style: .bold)
        wrapped(italicStar, markerLength: { _ in 1 }, style: .italic)
        wrapped(italicUnderscore, markerLength: { _ in 1 }, style: .italic)
        wrapped(strike, markerLength: { _ in 2 }, style: .strikethrough)

        each(link) { m in
            let textRange = m.range(at: 1)
            spans.append(MarkdownSpan(textRange, .link))
            spans.append(MarkdownSpan(NSRange(location: m.range.location, length: 1), .syntax))
            spans.append(MarkdownSpan(NSRange(location: NSMaxRange(textRange), length: NSMaxRange(m.range) - NSMaxRange(textRange)), .syntax))
        }

        return spans
    }
}
