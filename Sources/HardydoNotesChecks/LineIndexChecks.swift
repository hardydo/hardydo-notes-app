import Foundation
import HardydoNotesCore

func runLineIndexChecks() {
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
            index.update(text, edited: NSRange(location: location, length: insert.length), delta: insert.length - length)
            if index != LineIndex(text) { mismatches += 1 }
        }
    }
    checkEqual(mismatches, 0, "line starts kept edit by edit match a full rescan")
    let sample = LineIndex("one\ntwo\r\nthree")
    checkEqual(sample.starts, [0, 4, 9], "CR LF counts as one line break")
    checkEqual(sample.lineNumber(at: 5), 2, "a location maps to its 1-based line")
}
