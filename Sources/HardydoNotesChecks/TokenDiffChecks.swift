import Foundation
import HardydoNotesCore

/// Per character, the kind whose colour, underline and strikethrough show there; -1 is text an edit left unknown.
private typealias Paint = [[Int?]]

private func paint(_ tokens: [SyntaxToken], over state: inout Paint, in span: NSRange) {
    for index in span.location..<NSMaxRange(span) { state[index] = [nil, nil, nil] }
    for token in tokens {
        let clipped = NSIntersectionRange(token.range, span)
        guard clipped.length > 0 else { continue }
        let kind = SyntaxKind.allCases.firstIndex(of: token.kind)
        let keys = token.kind == .strike ? [0, 2] : token.kind == .link ? [0, 1] : [0]
        for index in clipped.location..<NSMaxRange(clipped) {
            for key in keys { state[index][key] = kind }
        }
    }
}

func runTokenDiffChecks() {
    let a = SyntaxToken(NSRange(location: 0, length: 3), .keyword)
    let b = SyntaxToken(NSRange(location: 5, length: 4), .string)
    check(TokenDiff.changedSpan(old: [a, b], new: [a, b], oldLength: 12, newLength: 12, unchangedPrefix: .max, unchangedSuffix: .max) == nil, "identical passes with no edit redo nothing")
    let typedInside = TokenDiff.changedSpan(old: [a, b], new: [a, SyntaxToken(NSRange(location: 5, length: 5), .string)], oldLength: 12, newLength: 13, unchangedPrefix: 7, unchangedSuffix: 5)
    checkEqual(typedInside, NSRange(location: 5, length: 5), "typing inside a token redoes just that token")
    let typedBefore = TokenDiff.changedSpan(old: [a, b], new: [a, SyntaxToken(NSRange(location: 6, length: 4), .string)], oldLength: 12, newLength: 13, unchangedPrefix: 4, unchangedSuffix: 8)
    checkEqual(typedBefore, NSRange(location: 4, length: 1), "typing between tokens redoes only the typed text; the token after it moves with its colour")
    let removed = TokenDiff.changedSpan(old: [a, b], new: [a], oldLength: 12, newLength: 8, unchangedPrefix: 5, unchangedSuffix: 3)
    check(removed == nil, "a token deleted along with its text needs no redo")

    var generator = SystemRandomNumberGenerator()
    let pieces = ["{", "}", "\"k\": ", "\"v\"", ", ", "12", "\n", " ", "[1, 2]", "true", "\"", ":", "// c", "/*", "*/"]
    var mismatches = 0
    for round in 0..<400 {
        let language: ContentLanguage = round.isMultiple(of: 2) ? .json : .javascript
        let text = NSMutableString(string: (0..<Int.random(in: 0...20, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined())
        var tokens = SyntaxHighlighter.tokens(in: text as String, language: language)
        var state: Paint = Array(repeating: [nil, nil, nil], count: text.length)
        paint(tokens, over: &state, in: NSRange(location: 0, length: text.length))
        var length = text.length
        for _ in 0..<4 {
            var prefix = Int.max
            var suffix = Int.max
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                let location = Int.random(in: 0...text.length, using: &generator)
                let removedLength = Int.random(in: 0...min(3, text.length - location), using: &generator)
                let inserted = (0..<Int.random(in: 0...2, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined() as NSString
                text.replaceCharacters(in: NSRange(location: location, length: removedLength), with: inserted as String)
                state.replaceSubrange(location..<location + removedLength, with: Array(repeating: [-1, -1, -1], count: inserted.length))
                prefix = min(prefix, location)
                suffix = min(suffix, text.length - location - inserted.length)
            }
            let next = SyntaxHighlighter.tokens(in: text as String, language: language)
            if let span = TokenDiff.changedSpan(old: tokens, new: next, oldLength: length, newLength: text.length, unchangedPrefix: prefix, unchangedSuffix: suffix) {
                paint(next, over: &state, in: span)
            }
            var full: Paint = Array(repeating: [nil, nil, nil], count: text.length)
            paint(next, over: &full, in: NSRange(location: 0, length: text.length))
            if state != full { mismatches += 1 }
            tokens = next
            length = text.length
        }
    }
    checkEqual(mismatches, 0, "redoing only the changed span colours the text exactly as a full pass")
}
