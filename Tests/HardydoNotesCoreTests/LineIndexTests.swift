import Foundation
import HardydoNotesCore
import Testing

@Suite struct LineIndexTests {
    @Test func incrementalUpdatesMatchAFullRescan() {
        var generator = SystemRandomNumberGenerator()
        let pieces = ["a", "bc", "\n", "\r", "\r\n", "\u{2028}", "x\ny", "\n\n", "é"]
        var mismatches = 0
        for _ in 0..<400 {
            let text = NSMutableString(string: (0..<Int.random(in: 0...12, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined())
            var index = LineIndex(text)
            for _ in 0..<6 {
                let location = Int.random(in: 0...text.length, using: &generator)
                let length = Int.random(in: 0...(text.length - location), using: &generator)
                let insert = (0..<Int.random(in: 0...3, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined() as NSString
                text.replaceCharacters(in: NSRange(location: location, length: length), with: insert as String)
                let before = index.count
                let added = index.update(text, edited: NSRange(location: location, length: insert.length), delta: insert.length - length)
                let rescan = LineIndex(text)
                if index != rescan || added != rescan.count - before { mismatches += 1 }
                let longest = (0..<rescan.count).map { NSMaxRange(text.lineRange(for: NSRange(location: rescan.starts[$0], length: 0))) - rescan.starts[$0] }.max() ?? 0
                if index.maxLineLength(textLength: text.length) != longest { mismatches += 1 }
                for line in 0..<rescan.count {
                    var end = 0
                    text.getLineStart(nil, end: nil, contentsEnd: &end, for: NSRange(location: rescan.starts[line], length: 0))
                    if index.contentsEnd(ofLine: line, in: text) != end { mismatches += 1 }
                }
            }
        }
        #expect(mismatches == 0, "line starts, added-line counts, longest line and line ends kept edit by edit match a full rescan")
    }

    @Test func lineStartsAndLineNumbersCountCRLFAsOneBreak() {
        let sample = LineIndex("one\ntwo\r\nthree")
        #expect(sample.starts == [0, 4, 9], "CR LF counts as one line break")
        #expect(sample.lineNumber(at: 5) == 2, "a location maps to its 1-based line")
        #expect(sample.line(at: 9) == 2, "a location maps to its 0-based line")
        #expect(LineIndex("a\n").starts == [0, 2], "a trailing line break starts an empty last line")
    }

    @Test func lineLookupsAgreeOnLFAndMixedBreaks() {
        let lfText = "one\ntwo\n\nfour" as NSString
        let lfIndex = LineIndex(lfText)
        #expect(lfIndex.starts == [0, 4, 8, 9], "line starts for LF text are where each line begins")
        #expect((0...lfText.length).map { lfIndex.line(at: $0) + 1 } == (0...lfText.length).map { lfIndex.lineNumber(at: $0) }, "the 0-based line and the 1-based line number agree")
        #expect([0, 3, 4, 8, 9, 13].map { lfIndex.line(at: $0) } == [0, 0, 1, 2, 3, 3], "a line break belongs to the line it ends")
        #expect(LineIndex("a\r\nb\rc" as NSString).starts == [0, 3, 5], "CRLF counts as one break and CR as another")
    }
}
