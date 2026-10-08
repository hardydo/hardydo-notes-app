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

public enum TextSearch {
    public static let maxMatches = 10_000

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

    // Empty matches (like a bare ^) are skipped: they cannot be highlighted and would replace nothing.
    public static func matches(of expression: NSRegularExpression, in text: String, limit: Int = maxMatches) -> [NSRange] {
        var ranges: [NSRange] = []
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, stop in
            guard let range = match?.range, range.length > 0 else { return }
            ranges.append(range)
            if ranges.count >= limit { stop.pointee = true }
        }
        return ranges
    }

    public static func lineMatches(of expression: NSRegularExpression, in text: String, limit: Int) -> [LineMatch] {
        let string = text as NSString
        var results: [LineMatch] = []
        var line = 1
        var counted = 0
        for range in matches(of: expression, in: text, limit: limit) {
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
        let result = NSMutableString(string: text)
        var count = 0
        let found = expression.matches(in: text, range: NSRange(location: 0, length: result.length)).filter { $0.range.length > 0 }
        for match in found.reversed() {
            result.replaceCharacters(in: match.range, with: expression.replacementString(for: match, in: text, offset: 0, template: template))
            count += 1
        }
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
