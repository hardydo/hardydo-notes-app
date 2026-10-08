import Foundation

/// One line of the sidebar: a group header, or a note with the group it is listed under.
public enum SidebarRow: Identifiable, Equatable, Sendable {
    case header(NoteGroup)
    case note(Note, group: NoteGroup?)

    public var id: UUID {
        switch self {
        case .header(let group): group.id
        case .note(let note, _): note.id
        }
    }

    fileprivate var key: RowKey {
        switch self {
        case .header(let group): .header(group.id)
        case .note(let note, let group): .note(note.id, group?.id)
        }
    }
}

private enum RowKey: Equatable {
    case header(NoteGroup.ID)
    case note(Note.ID, NoteGroup.ID?)
}

/// Where a dragged row or group can land, and what the notes and groups become if it lands there.
public struct SidebarReorderPlan: Sendable {
    public struct Result: Equatable, Sendable {
        public let order: [Note.ID]
        public let groups: NoteGroups
    }

    public let rows: [UUID]
    public let block: [UUID]
    /// Keyed by the insertion index among the rows left once the block is lifted out.
    public let slots: [Int: Result]
    /// The gaps at the end of an open group, where a note in the upper half joins the group and one in the lower half stays out.
    public let upperSlots: [Int: Result]
    /// Collapsed groups the dragged note can be dropped onto.
    public let into: Set<NoteGroup.ID>
    /// A group's last note starts in the upper half of its own gap, so lifting it does not take it out of the group.
    public let startsUpper: Bool
}

extension NoteGroups {
    public func rows(for notes: [Note]) -> [SidebarRow] {
        entries(for: notes).flatMap { entry -> [SidebarRow] in
            switch entry {
            case .note(let note):
                [.note(note, group: nil)]
            case .group(let group, let members):
                [.header(group)] + (group.isCollapsed ? [] : members.map { .note($0, group: group) })
            }
        }
    }

    /*
     Every landing place is tried up front and kept only if the sidebar would list the result exactly as
     shown while dragging, so pinned notes, pinned groups and group blocks never end up somewhere else on drop.
     */
    public func reorderPlan(moving id: UUID, in notes: [Note]) -> SidebarReorderPlan? {
        let rows = rows(for: notes)
        guard let start = rows.firstIndex(where: { $0.id == id }) else { return nil }
        var end = start + 1
        var movingNote: (note: Note, group: NoteGroup.ID?)?
        switch rows[start] {
        case .header(let group):
            while end < rows.count, case .note(_, let member) = rows[end], member?.id == group.id { end += 1 }
        case .note(let note, let group):
            movingNote = (note, group?.id)
        }
        let block = Array(rows[start..<end])
        var remaining = rows
        remaining.removeSubrange(start..<end)
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func result(at index: Int, joining target: NoteGroup.ID?) -> SidebarReorderPlan.Result? {
            var updated = self
            var shown = block.map(\.key)
            if let movingNote {
                if target != movingNote.group {
                    if let target { updated.add(movingNote.note.id, to: target) } else { updated.remove(movingNote.note.id) }
                }
                shown = [.note(movingNote.note.id, target)]
            }
            let layout = remaining[..<index].map(\.key) + shown + remaining[index...].map(\.key)
            let order = flatten(layout, notes: notes, excluding: id)
            let sorted = order.compactMap { byID[$0] }
            let listed = updated.rows(for: sorted.filter(\.isPinned) + sorted.filter { !$0.isPinned }).map(\.key)
            let expected = layout.filter { key in
                if case .header(let group) = key { return updated.group(group) != nil }
                return true
            }
            return listed == expected ? .init(order: order, groups: updated) : nil
        }

        var slots: [Int: SidebarReorderPlan.Result] = [:]
        var upperSlots: [Int: SidebarReorderPlan.Result] = [:]
        for index in 0...remaining.count {
            let lanes = movingNote == nil ? (lower: nil, upper: nil) : Self.lanes(at: index, in: remaining)
            slots[index] = result(at: index, joining: lanes.lower)
            if lanes.upper != lanes.lower { upperSlots[index] = result(at: index, joining: lanes.upper) }
        }

        var into: Set<NoteGroup.ID> = []
        var startsUpper = false
        if let movingNote {
            for row in remaining {
                if case .header(let group) = row, group.isCollapsed, group.id != movingNote.group { into.insert(group.id) }
            }
            let own = Self.lanes(at: start, in: remaining)
            startsUpper = own.upper != own.lower && own.upper == movingNote.group
        }
        return SidebarReorderPlan(
            rows: rows.map(\.id), block: block.map(\.id), slots: slots, upperSlots: upperSlots, into: into, startsUpper: startsUpper
        )
    }

    /// The group a note dropped at `index` joins: under an open group's header or between two of its notes it joins;
    /// in the gap at a group's end only the upper half joins.
    private static func lanes(at index: Int, in rows: [SidebarRow]) -> (lower: NoteGroup.ID?, upper: NoteGroup.ID?) {
        let next = index < rows.count ? rows[index] : nil
        switch index > 0 ? rows[index - 1] : nil {
        case .header(let group)?:
            let lane = group.isCollapsed ? nil : group.id
            return (lane, lane)
        case .note(_, let group?)?:
            if case .note(_, let following?)? = next, following.id == group.id { return (group.id, group.id) }
            return (nil, group.id)
        default:
            return (nil, nil)
        }
    }

    private func flatten(_ layout: [RowKey], notes: [Note], excluding id: UUID) -> [Note.ID] {
        layout.flatMap { key -> [Note.ID] in
            switch key {
            case .note(let note, _):
                return [note]
            case .header(let groupID):
                guard group(groupID)?.isCollapsed == true else { return [] }
                return notes.filter { $0.id != id && group(of: $0.id)?.id == groupID }.map(\.id)
            }
        }
    }
}
