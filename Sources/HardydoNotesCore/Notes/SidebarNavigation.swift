import Foundation

extension NoteGroups {
    /// The note ↑ or ↓ lands on among the shown notes, app notes first, then opened files; nil when nothing is shown.
    public func step(from selection: Note.ID?, by offset: Int, appNotes: [Note], fileNotes: [Note]) -> Note.ID? {
        let shown = visibleNotes(appNotes) + fileNotes
        guard !shown.isEmpty else { return nil }
        if let current = shown.firstIndex(where: { $0.id == selection }) {
            return shown[min(max(current + offset, 0), shown.count - 1)].id
        }
        // The open note may sit in a collapsed group: step from its place in the full list to the next note shown.
        let all = orderedNotes(appNotes) + fileNotes
        guard let position = all.firstIndex(where: { $0.id == selection }) else { return shown[0].id }
        let shownIDs = Set(shown.map(\.id))
        let ahead = offset > 0 ? Array(all[(position + 1)...]) : all[..<position].reversed()
        return (ahead.first { shownIDs.contains($0.id) } ?? (offset > 0 ? shown[shown.count - 1] : shown[0])).id
    }
}
