import Foundation

public enum QuickOpenRanking {
    /// Open tabs first, as recently used files are in VS Code, then every other note in sidebar order, each once.
    public static func candidates(openTabs: [Note.ID], listed: [NoteSummary]) -> [NoteSummary] {
        let byID = Dictionary(listed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let open = openTabs.compactMap { byID[$0] }
        let openIDs = Set(open.map(\.id))
        return open + listed.filter { !openIDs.contains($0.id) }
    }
}
