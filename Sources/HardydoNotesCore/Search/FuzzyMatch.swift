import Foundation

/// Quick Open matching: the query's characters must appear in order; runs and word starts score higher.
public enum FuzzyMatch {
    /// A query lowered and stripped once, then scored against every candidate.
    public struct Query: Sendable {
        let needle: [Character]

        public init(_ query: String) {
            needle = Array(query.lowercased().filter { !$0.isWhitespace })
        }

        public var isEmpty: Bool { needle.isEmpty }

        public func score(_ candidate: String) -> Int? {
            guard !needle.isEmpty else { return 0 }
            let haystack = Array(candidate.lowercased())
            var score = 0
            var index = 0
            var previous: Int?
            for (position, character) in haystack.enumerated() where index < needle.count && character == needle[index] {
                score += 1
                if position == 0 || !(haystack[position - 1].isLetter || haystack[position - 1].isNumber) { score += 8 }
                if let previous, previous == position - 1 { score += 5 }
                previous = position
                index += 1
            }
            guard index == needle.count else { return nil }
            return score - haystack.count / 10
        }
    }

    public static func score(_ query: String, in candidate: String) -> Int? {
        Query(query).score(candidate)
    }

    /// Candidates that match, best first; ties keep their original order.
    public static func rank<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        let query = Query(query)
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in query.score(text(item)).map { (item, $0, offset) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}
