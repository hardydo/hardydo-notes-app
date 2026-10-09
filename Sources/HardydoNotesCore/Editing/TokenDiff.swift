import Foundation

/// The part of the text whose colouring changed between two tokenizer passes.
public enum TokenDiff {
    /*
     `unchangedPrefix` and `unchangedSuffix` are how much of the text at each end no edit has touched since `old`
     was applied. Tokens wholly inside those ends and equal in both passes (the suffix ones shifted by the change
     in length) keep their colour; everything between them is redone.
     */
    public static func changedSpan(old: [SyntaxToken], new: [SyntaxToken], oldLength: Int, newLength: Int, unchangedPrefix: Int, unchangedSuffix: Int) -> NSRange? {
        let delta = newLength - oldLength
        var head = 0
        while head < old.count, head < new.count, old[head] == new[head], NSMaxRange(old[head].range) <= unchangedPrefix {
            head += 1
        }
        var oldTail = old.count
        var newTail = new.count
        while oldTail > head, newTail > head {
            let before = old[oldTail - 1].range
            let after = new[newTail - 1]
            guard before.location >= oldLength - unchangedSuffix, after.kind == old[oldTail - 1].kind,
                  after.range == NSRange(location: before.location + delta, length: before.length) else { break }
            oldTail -= 1
            newTail -= 1
        }
        var start = min(unchangedPrefix, newLength)
        var end = max(newLength - unchangedSuffix, start)
        for token in old[head..<oldTail] {
            start = min(start, token.range.location)
            let tokenEnd = NSMaxRange(token.range)
            end = max(end, min(tokenEnd >= oldLength - unchangedSuffix ? tokenEnd + delta : tokenEnd, newLength))
        }
        for token in new[head..<newTail] {
            start = min(start, token.range.location)
            end = max(end, NSMaxRange(token.range))
        }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
