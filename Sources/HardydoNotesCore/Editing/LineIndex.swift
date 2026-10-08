import Foundation

/// Where every line starts, with the same breaks as `NSString.lineRange`, kept current edit by edit.
public struct LineIndex: Equatable, Sendable {
    public private(set) var starts: [Int]

    public init(_ text: NSString) {
        starts = [0] + Self.breaks(in: text, from: 0, to: text.length)
    }

    public var count: Int { starts.count }

    /// 1-based number of the line holding `location`.
    public func lineNumber(at location: Int) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= location { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /*
     `edited` is the changed range in the new text and `delta` the change in length, as NSTextStorage reports
     them. Only the lines around the edit are rescanned; one extra character on each side covers a CR LF pair
     split or joined by the edit.
     */
    public mutating func update(_ text: NSString, edited: NSRange, delta: Int) {
        let oldEnd = NSMaxRange(edited) - delta
        let first = max(lineNumber(at: max(edited.location - 1, 0)) - 1, 0)
        var tail = starts.count
        while tail > first + 1, starts[tail - 1] > oldEnd + 1 { tail -= 1 }
        let kept = starts[tail...].map { $0 + delta }
        let scanEnd = min(kept.first.map { $0 - 1 } ?? text.length, text.length)
        let middle = Self.breaks(in: text, from: starts[first], to: max(scanEnd, starts[first])).filter { $0 < (kept.first ?? .max) }
        starts = Array(starts[...first]) + middle + kept
    }

    private static func breaks(in text: NSString, from start: Int, to end: Int) -> [Int] {
        guard end > start else { return [] }
        let length = text.length
        var characters = [unichar](repeating: 0, count: min(end + 1, length) - start)
        text.getCharacters(&characters, range: NSRange(location: start, length: characters.count))
        var result: [Int] = []
        var offset = 0
        while start + offset < end {
            switch characters[offset] {
            case 10, 0x85, 0x2028, 0x2029:
                result.append(start + offset + 1)
            case 13:
                if offset + 1 < characters.count, characters[offset + 1] == 10 { offset += 1 }
                result.append(start + offset + 1)
            default:
                break
            }
            offset += 1
        }
        return result
    }
}
