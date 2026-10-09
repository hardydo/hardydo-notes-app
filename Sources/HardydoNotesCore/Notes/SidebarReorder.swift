import Foundation

/// One line of the sidebar: a group header, or a note with the group it is listed under.
public enum SidebarRow: Identifiable, Equatable, Sendable {
    case header(NoteGroup)
    case note(NoteSummary, group: NoteGroup?)

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

/*
 Where a dragged row or group can land, and what the notes and groups become if it lands there. Each landing place
 costs a pass over the whole list, so places are worked out only when the drag reaches them, and remembered.
 */
public final class SidebarReorderPlan {
    public struct Result: Equatable, Sendable {
        public let order: [Note.ID]
        public let groups: NoteGroups
    }

    public let rows: [UUID]
    public let block: [UUID]
    /// Collapsed groups the dragged note can be dropped onto.
    public let into: Set<NoteGroup.ID>
    /// A group's last note starts in the upper half of its own gap, so lifting it does not take it out of the group.
    public let startsUpper: Bool
    /// Insertion indexes among the rows left once the block is lifted out run from 0 to `slotCount - 1`.
    public let slotCount: Int
    private let lanes: (Int) -> (lower: NoteGroup.ID?, upper: NoteGroup.ID?)
    private let compute: (Int, NoteGroup.ID?) -> Result?
    private var memo: [Int: Result?] = [:]
    private var upperMemo: [Int: Result?] = [:]

    init(
        rows: [UUID], block: [UUID], into: Set<NoteGroup.ID>, startsUpper: Bool, slotCount: Int,
        lanes: @escaping (Int) -> (lower: NoteGroup.ID?, upper: NoteGroup.ID?), compute: @escaping (Int, NoteGroup.ID?) -> Result?
    ) {
        self.rows = rows
        self.block = block
        self.into = into
        self.startsUpper = startsUpper
        self.slotCount = slotCount
        self.lanes = lanes
        self.compute = compute
    }

    /// The gaps at the end of an open group have two halves: a note in the upper half joins the group, one in the lower half stays out.
    public func hasUpperHalf(at index: Int) -> Bool {
        guard (0..<slotCount).contains(index) else { return false }
        let lanes = lanes(index)
        return lanes.upper != lanes.lower
    }

    /// What dropping at `index` gives, or nil when the sidebar would not list the result as it was shown while dragging.
    public func result(at index: Int, upper: Bool) -> Result? {
        guard (0..<slotCount).contains(index), !upper || hasUpperHalf(at: index) else { return nil }
        if let known = upper ? upperMemo[index] : memo[index] { return known }
        let lanes = lanes(index)
        let result = compute(index, upper ? lanes.upper : lanes.lower)
        if upper { upperMemo[index] = result } else { memo[index] = result }
        return result
    }
}

extension NoteGroups {
    public func rows(for notes: [Note]) -> [SidebarRow] {
        entries(for: notes).flatMap { entry -> [SidebarRow] in
            switch entry {
            case .note(let note):
                [.note(note.summary, group: nil)]
            case .group(let group, let members):
                [.header(group)] + (group.isCollapsed ? [] : members.map { .note($0.summary, group: group) })
            }
        }
    }

    /// The rows `rows(for:)` would list for these notes, worked out from their ids alone.
    fileprivate func rowKeys(ids: [Note.ID], pinned: Set<Note.ID>) -> [RowKey] {
        entryPlaces(count: ids.count, id: { ids[$0] }, isPinned: { pinned.contains(ids[$0]) }).flatMap { place -> [RowKey] in
            switch place {
            case .note(let index):
                [.note(ids[index], nil)]
            case .group(let group, let members):
                [.header(group.id)] + (group.isCollapsed ? [] : members.map { .note(ids[$0], group.id) })
            }
        }
    }

    /*
     A landing place is kept only if the sidebar would list the result exactly as shown while dragging, so
     pinned notes, pinned groups and group blocks never end up somewhere else on drop.
     */
    public func reorderPlan(moving id: UUID, in notes: [Note]) -> SidebarReorderPlan? {
        let rows = rows(for: notes)
        guard let start = rows.firstIndex(where: { $0.id == id }) else { return nil }
        var end = start + 1
        var movingNote: (id: Note.ID, group: NoteGroup.ID?)?
        switch rows[start] {
        case .header(let group):
            while end < rows.count, case .note(_, let member) = rows[end], member?.id == group.id { end += 1 }
        case .note(let note, let group):
            movingNote = (note.id, group?.id)
        }
        let block = Array(rows[start..<end])
        var remaining = rows
        remaining.removeSubrange(start..<end)
        let known = Set(notes.map(\.id))
        let pinned = Set(notes.filter(\.isPinned).map(\.id))
        var hidden: [NoteGroup.ID: [Note.ID]] = [:]
        for note in notes where note.id != id {
            if let group = group(of: note.id), group.isCollapsed { hidden[group.id, default: []].append(note.id) }
        }

        func result(at index: Int, joining target: NoteGroup.ID?) -> SidebarReorderPlan.Result? {
            var updated = self
            var shown = block.map(\.key)
            if let movingNote {
                if target != movingNote.group {
                    if let target { updated.add(movingNote.id, to: target) } else { updated.remove(movingNote.id) }
                }
                shown = [.note(movingNote.id, target)]
            }
            let layout = remaining[..<index].map(\.key) + shown + remaining[index...].map(\.key)
            let order = layout.flatMap { key -> [Note.ID] in
                switch key {
                case .note(let note, _): [note]
                case .header(let group): hidden[group] ?? []
                }
            }
            let sorted = order.filter(known.contains)
            let listed = updated.rowKeys(ids: sorted.filter(pinned.contains) + sorted.filter { !pinned.contains($0) }, pinned: pinned)
            let expected = layout.filter { key in
                if case .header(let group) = key { return updated.group(group) != nil }
                return true
            }
            return listed == expected ? .init(order: order, groups: updated) : nil
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
        let isNote = movingNote != nil
        return SidebarReorderPlan(
            rows: rows.map(\.id), block: block.map(\.id), into: into, startsUpper: startsUpper, slotCount: remaining.count + 1,
            lanes: { isNote ? Self.lanes(at: $0, in: remaining) : (nil, nil) },
            compute: result
        )
    }

    /*
     The group a note dropped at `index` joins: under an open group's header or between two of its notes it joins;
     in the gap at a group's end only the upper half joins.
     */
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
}
