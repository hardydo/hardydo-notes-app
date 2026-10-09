import Foundation

public struct SearchOptions: Equatable, Hashable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var regex: Bool

    public init(caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
    }
}

public struct LineMatch: Equatable, Sendable {
    public let range: NSRange
    public let line: Int
    public let before: String
    public let matched: String
    public let after: String
}

/// What a search of every note reads from one note.
public struct SearchableNote: Sendable {
    public let id: UUID
    public let revision: Int
    public let title: String
    public let isFile: Bool
    public let body: String

    public init(id: UUID, revision: Int, title: String, isFile: Bool, body: String) {
        self.id = id
        self.revision = revision
        self.title = title
        self.isFile = isFile
        self.body = body
    }
}

public struct NoteMatches: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let isFile: Bool
    public let lines: [LineMatch]
    /// More lines matched than are listed.
    public let isClipped: Bool
}

/// The lines each note matched for one query, so a note whose text has not changed is not searched again.
public struct SearchMemo: Sendable {
    let query: String
    let options: SearchOptions
    var notes: [UUID: (revision: Int, lines: [LineMatch])] = [:]

    public init(query: String, options: SearchOptions) {
        self.query = query
        self.options = options
    }
}

public enum TextSearch {
    public static let maxMatches = 10_000
    public static let linesPerNote = 50
    public static let linesInAll = 2_000
    /// In regex mode longer lines are not searched: one pattern that backtracks badly could run for minutes on them.
    public static let longLineLimit = 10_000

    /// Nil for an empty query; throws when the regular expression does not compile.
    public static func expression(for query: String, options: SearchOptions) throws -> NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        // \b fails next to punctuation, so a word edge is "no letter, digit or underscore on that side".
        if options.wholeWord {
            pattern = "(?<![\\p{L}\\p{N}_])(?:" + pattern + ")(?![\\p{L}\\p{N}_])"
        }
        var flags: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.caseSensitive { flags.insert(.caseInsensitive) }
        return try NSRegularExpression(pattern: pattern, options: flags)
    }

    /// The matches in `text`, or nil when the regular expression does not compile.
    public static func ranges(of query: String, options: SearchOptions, in text: String) -> [NSRange]? {
        do {
            guard let expression = try expression(for: query, options: options) else { return [] }
            return matches(of: expression, in: text, skippingLongLines: options.regex)
        } catch {
            return nil
        }
    }

    /*
     Empty matches (like a bare ^) are skipped: they cannot be highlighted and would replace nothing. A cancelled
     task stops early with what it found so far, which its caller drops.
     */
    public static func matches(of expression: NSRegularExpression, in text: String, limit: Int = maxMatches, skippingLongLines: Bool = false) -> [NSRange] {
        let string = text as NSString
        let spans = skippingLongLines ? shortLineSpans(in: string) : [NSRange(location: 0, length: string.length)]
        var ranges: [NSRange] = []
        for span in spans where ranges.count < limit && !Task.isCancelled {
            expression.enumerateMatches(in: string as String, range: span) { match, _, stop in
                guard let range = match?.range, range.length > 0 else { return }
                ranges.append(range)
                if ranges.count >= limit || Task.isCancelled { stop.pointee = true }
            }
        }
        return ranges
    }

    static func shortLineSpans(in string: NSString) -> [NSRange] {
        var spans: [NSRange] = []
        var start = 0
        var index = 0
        while index < string.length {
            let line = string.lineRange(for: NSRange(location: index, length: 0))
            if line.length > longLineLimit {
                if index > start { spans.append(NSRange(location: start, length: index - start)) }
                start = NSMaxRange(line)
            }
            index = NSMaxRange(line)
        }
        if string.length > start { spans.append(NSRange(location: start, length: string.length - start)) }
        return spans
    }

    /*
     Every note in order, until the lines found reach `linesInAll`. Nil when the task is cancelled, or when the
     regular expression does not compile; `memo` carries the lines of unchanged notes from one run to the next.
     */
    public static func searchAll(_ notes: [SearchableNote], query: String, options: SearchOptions, memo: inout SearchMemo) -> [NoteMatches]? {
        guard let expression = try? expression(for: query, options: options) else { return query.isEmpty ? [] : nil }
        let previous = memo.query == query && memo.options == options ? memo.notes : [:]
        var found: [UUID: (revision: Int, lines: [LineMatch])] = [:]
        var results: [NoteMatches] = []
        var budget = linesInAll
        for note in notes where budget > 0 {
            let lines: [LineMatch]
            if let kept = previous[note.id], kept.revision == note.revision {
                lines = kept.lines
            } else {
                lines = lineMatches(of: expression, in: note.body, limit: linesPerNote + 1, skippingLongLines: options.regex)
                if Task.isCancelled { return nil }
            }
            found[note.id] = (note.revision, lines)
            guard !lines.isEmpty else { continue }
            let listed = Array(lines.prefix(min(linesPerNote, budget)))
            budget -= listed.count
            results.append(NoteMatches(id: note.id, title: note.title, isFile: note.isFile, lines: listed, isClipped: lines.count > listed.count))
        }
        memo = SearchMemo(query: query, options: options)
        memo.notes = found
        return results
    }

    /// The match after the selection, or before it going back, wrapping around at either end.
    public static func nextMatch(in ranges: [NSRange], from selection: NSRange, forward: Bool) -> NSRange? {
        guard !ranges.isEmpty else { return nil }
        return forward
            ? ranges.first { $0.location > selection.location || ($0.location == selection.location && selection.length == 0) } ?? ranges[0]
            : ranges.last { $0.location < selection.location } ?? ranges[ranges.count - 1]
    }

    public static func firstMatch(in ranges: [NSRange], atOrAfter location: Int) -> NSRange? {
        ranges.first { $0.location >= location } ?? ranges.first
    }

    public static func lineMatches(of expression: NSRegularExpression, in text: String, limit: Int, skippingLongLines: Bool = false) -> [LineMatch] {
        let string = text as NSString
        var results: [LineMatch] = []
        var line = 1
        var counted = 0
        for range in matches(of: expression, in: text, limit: limit, skippingLongLines: skippingLongLines) {
            line += newlines(in: string, from: counted, to: range.location)
            counted = range.location
            let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
            let contentEnd = lineEnd(of: lineRange, in: string)
            let before = string.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
            let matchEnd = min(NSMaxRange(range), contentEnd)
            let matched = string.substring(with: NSRange(location: range.location, length: max(matchEnd - range.location, 0)))
            let after = matchEnd < contentEnd ? string.substring(with: NSRange(location: matchEnd, length: contentEnd - matchEnd)) : ""
            results.append(LineMatch(
                range: range,
                line: line,
                before: clipped(before.replacingOccurrences(of: "\t", with: " "), keepingEnd: true),
                matched: String(matched.prefix(200)),
                after: clipped(after, keepingEnd: false)
            ))
        }
        return results
    }

    /// What the match at `range` turns into; regex templates may use $1-style groups, plain text is inserted as typed.
    public static func replacement(for range: NSRange, in text: String, expression: NSRegularExpression, template: String, options: SearchOptions) -> String? {
        guard let match = expression.firstMatch(in: text, options: [.withTransparentBounds, .withoutAnchoringBounds], range: range),
              match.range == range else { return nil }
        let template = options.regex ? template : NSRegularExpression.escapedTemplate(for: template)
        return expression.replacementString(for: match, in: text, offset: 0, template: template)
    }

    public static func replacingAll(in text: String, expression: NSRegularExpression, template: String, options: SearchOptions) -> (text: String, count: Int) {
        let template = options.regex ? template : NSRegularExpression.escapedTemplate(for: template)
        let source = text as NSString
        let result = NSMutableString(capacity: source.length)
        var copied = 0
        var count = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) where match.range.length > 0 {
            result.append(source.substring(with: NSRange(location: copied, length: match.range.location - copied)))
            result.append(expression.replacementString(for: match, in: text, offset: 0, template: template))
            copied = NSMaxRange(match.range)
            count += 1
        }
        result.append(source.substring(from: copied))
        return (result as String, count)
    }

    private static func newlines(in string: NSString, from start: Int, to end: Int) -> Int {
        var count = 0
        var index = start
        while index < end {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(lineRange)
            guard next <= end, next > index else { break }
            count += 1
            index = next
        }
        return count
    }

    private static func lineEnd(of lineRange: NSRange, in string: NSString) -> Int {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location, let scalar = Unicode.Scalar(string.character(at: end - 1)),
              CharacterSet.newlines.contains(scalar) {
            end -= 1
        }
        return end
    }

    // Little text is kept before the match so it stays visible in a narrow result list.
    private static func clipped(_ text: String, keepingEnd: Bool) -> String {
        if keepingEnd {
            let trimmed = String(text.drop { $0 == " " })
            return trimmed.count > 24 ? "…" + trimmed.suffix(20) : trimmed
        }
        return text.count > 120 ? text.prefix(120) + "…" : text
    }
}
