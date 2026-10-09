import Foundation
import HardydoNotesCore
import Testing

private func layout(_ groups: NoteGroups, _ list: [Note]) -> [String] {
    groups.rows(for: list.filter(\.isPinned) + list.filter { !$0.isPinned }).map { row in
        switch row {
        case .header(let group): group.name + (group.isCollapsed ? "+" : ":")
        case .note(let note, let group): (group == nil ? "" : "  ") + note.title
        }
    }
}

// Drops the lifted block right after `anchor` (nil = at the very top) and lists the result.
private func drop(_ moving: UUID, after anchor: UUID?, upper: Bool = false, _ groups: NoteGroups, _ list: [Note]) -> [String]? {
    guard let plan = groups.reorderPlan(moving: moving, in: list) else { return nil }
    let remaining = plan.rows.filter { !plan.block.contains($0) }
    let index = anchor.map { (remaining.firstIndex(of: $0) ?? -2) + 1 } ?? 0
    guard let result = plan.result(at: index, upper: upper) else { return nil }
    let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    return layout(result.groups, result.order.compactMap { byID[$0] })
}

private func workGroup() -> (notes: [Note], id: [UUID], groups: NoteGroups, work: UUID) {
    let notes = (0..<5).map { Note(body: "n\($0)") }
    let id = notes.map(\.id)
    var groups = NoteGroups()
    let work = groups.create(name: "Work", with: id[1])
    groups.add(id[2], to: work)
    return (notes, id, groups, work)
}

@Suite struct SidebarReorderTests {
    @Test func sidebarListsAGroupHeaderThenItsNotes() {
        let (notes, _, groups, _) = workGroup()
        #expect(layout(groups, notes) == ["n0", "Work:", "  n1", "  n2", "n3", "n4"], "the sidebar lists a group header then its notes")
    }

    @Test func notesDroppedInsideAGroupJoinIt() {
        let (notes, id, groups, work) = workGroup()
        #expect(drop(id[3], after: id[1], groups, notes) == ["n0", "Work:", "  n1", "  n3", "  n2", "n4"], "a note dropped between two notes of a group joins it")
        #expect(drop(id[3], after: work, groups, notes) == ["n0", "Work:", "  n3", "  n1", "  n2", "n4"], "a note dropped right under a group header joins the group")
    }

    @Test func dropAtAGroupEndDependsOnTheHalfOfTheGap() {
        let (notes, id, groups, _) = workGroup()
        #expect(drop(id[0], after: id[2], groups, notes) == ["Work:", "  n1", "  n2", "n0", "n3", "n4"], "a loose note dropped low in the gap at a group's end stays loose")
        #expect(drop(id[0], after: id[2], upper: true, groups, notes) == ["Work:", "  n1", "  n2", "  n0", "n3", "n4"], "a loose note dropped high in the gap at a group's end joins the group as its last note")
        #expect(drop(id[4], after: id[2], upper: true, groups, notes) == ["n0", "Work:", "  n1", "  n2", "  n4", "n3"], "a loose note from below joins a group at its end")
        #expect(groups.reorderPlan(moving: id[3], in: notes)?.result(at: 0, upper: true) == nil, "only the gap at a group's end has two halves")
    }

    @Test func draggingNotesOutOfOrWithinTheirGroup() {
        let (notes, id, groups, _) = workGroup()
        #expect(drop(id[2], after: id[4], groups, notes) == ["n0", "Work:", "  n1", "n3", "n4", "n2"], "a note dragged out of a group leaves it")
        #expect(drop(id[1], after: id[2], upper: true, groups, notes) == ["n0", "Work:", "  n2", "  n1", "n3", "n4"], "a note keeps its group when moved high into the group's end")
        #expect(drop(id[1], after: id[2], groups, notes) == ["n0", "Work:", "  n2", "n1", "n3", "n4"], "a note moved low into the gap at its group's end leaves the group")
        #expect(groups.reorderPlan(moving: id[2], in: notes)?.startsUpper == true, "lifting a group's last note keeps it in the group")
        #expect(groups.reorderPlan(moving: id[3], in: notes)?.startsUpper == false, "lifting the loose note under a group keeps it loose")
    }

    @Test func draggedGroupMovesWithAllItsNotes() {
        let (notes, id, groups, work) = workGroup()
        #expect(drop(work, after: id[4], groups, notes) == ["n0", "n3", "n4", "Work:", "  n1", "  n2"], "a dragged group moves with all of its notes")
        #expect(drop(work, after: nil, groups, notes) == ["Work:", "  n1", "  n2", "n0", "n3", "n4"], "a group can move to the top")
    }

    @Test func groupsNeverLandInsideAnotherGroup() {
        let (notes, id, groups, work) = workGroup()
        var home = groups
        let homeID = home.create(name: "Home", with: id[3])
        home.add(id[4], to: homeID)
        #expect(drop(work, after: id[3], home, notes) == nil, "a group never lands inside another group")
        #expect(drop(homeID, after: id[0], home, notes) == ["n0", "Home:", "  n3", "  n4", "Work:", "  n1", "  n2"], "groups swap places as blocks")
    }

    @Test func pinnedNotesStayAboveUnpinnedOnes() {
        let (notes, id, groups, _) = workGroup()
        var pinned = notes
        pinned[0].isPinned = true
        #expect(drop(id[3], after: nil, groups, pinned) == nil, "an unpinned note never moves above a pinned one")
        #expect(drop(id[0], after: nil, groups, pinned) == ["n0", "Work:", "  n1", "  n2", "n3", "n4"], "a pinned note stays among the pinned ones")
    }

    @Test func collapsedGroupsTakeDropsAndMoveWithTheirHiddenNotes() {
        let (notes, id, groups, work) = workGroup()
        var collapsed = groups
        collapsed.update(work) { $0.isCollapsed = true }
        let plan = collapsed.reorderPlan(moving: id[0], in: notes)
        #expect(plan?.into == [work], "a collapsed group takes a note dropped on its header")
        #expect(drop(id[0], after: work, collapsed, notes) == ["Work+", "n0", "n3", "n4"], "a note dropped after a collapsed group stays loose below it")
        #expect(drop(work, after: id[4], collapsed, notes) == ["n0", "n3", "n4", "Work+"], "a collapsed group moves with its hidden notes")
        let movedPlan = collapsed.reorderPlan(moving: work, in: notes)
        let moved = (0..<(movedPlan?.slotCount ?? 0)).lazy.compactMap { movedPlan?.result(at: $0, upper: false) }.first { $0.order.last == id[2] }
        #expect(moved?.order.suffix(2) == [id[1], id[2]], "hidden notes of a moved group keep their order")
    }

    @Test func landingResultDoesNotDependOnTheOrderPlacesAreAsked() {
        let (notes, id, groups, _) = workGroup()
        let forward = groups.reorderPlan(moving: id[0], in: notes)!
        let backward = groups.reorderPlan(moving: id[0], in: notes)!
        let ascending = (0..<forward.slotCount).flatMap { [forward.result(at: $0, upper: false), forward.result(at: $0, upper: true)] }
        let descending = (0..<backward.slotCount).reversed().flatMap { [backward.result(at: $0, upper: true), backward.result(at: $0, upper: false)] }
        #expect(ascending == Array(descending.reversed()), "a landing place gives the same result whatever order places are asked in")
        #expect(forward.result(at: forward.slotCount, upper: false) == nil && forward.result(at: -1, upper: false) == nil, "places outside the list are not landing places")
    }

    @Test func draggingTheLastNoteOutRemovesTheGroup() {
        let notes = (0..<5).map { Note(body: "n\($0)") }
        var single = NoteGroups()
        let solo = single.create(name: "Solo", with: notes[1].id)
        let leaving = single.reorderPlan(moving: notes[1].id, in: notes)?.result(at: 0, upper: false)
        #expect(leaving?.groups.group(solo) == nil, "dragging the last note out of a group removes the group")
    }
}
