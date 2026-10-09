import Foundation
import HardydoNotesCore

func runSidebarReorderChecks() {
    var notes = (0..<5).map { Note(body: "n\($0)") }
    let id = notes.map(\.id)
    var groups = NoteGroups()
    let work = groups.create(name: "Work", with: id[1])
    groups.add(id[2], to: work)

    func layout(_ groups: NoteGroups, _ list: [Note]) -> [String] {
        groups.rows(for: list.filter(\.isPinned) + list.filter { !$0.isPinned }).map { row in
            switch row {
            case .header(let group): group.name + (group.isCollapsed ? "+" : ":")
            case .note(let note, let group): (group == nil ? "" : "  ") + note.title
            }
        }
    }

    // Drops the lifted block right after `anchor` (nil = at the very top) and lists the result.
    func drop(_ moving: UUID, after anchor: UUID?, upper: Bool = false, _ groups: NoteGroups, _ list: [Note]) -> [String]? {
        guard let plan = groups.reorderPlan(moving: moving, in: list) else { return nil }
        let remaining = plan.rows.filter { !plan.block.contains($0) }
        let index = anchor.map { (remaining.firstIndex(of: $0) ?? -2) + 1 } ?? 0
        guard let result = plan.result(at: index, upper: upper) else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        return layout(result.groups, result.order.compactMap { byID[$0] })
    }

    checkEqual(layout(groups, notes), ["n0", "Work:", "  n1", "  n2", "n3", "n4"], "the sidebar lists a group header then its notes")
    checkEqual(drop(id[3], after: id[1], groups, notes), ["n0", "Work:", "  n1", "  n3", "  n2", "n4"],
               "a note dropped between two notes of a group joins it")
    checkEqual(drop(id[3], after: work, groups, notes), ["n0", "Work:", "  n3", "  n1", "  n2", "n4"],
               "a note dropped right under a group header joins the group")
    checkEqual(drop(id[0], after: id[2], groups, notes), ["Work:", "  n1", "  n2", "n0", "n3", "n4"],
               "a loose note dropped low in the gap at a group's end stays loose")
    checkEqual(drop(id[0], after: id[2], upper: true, groups, notes), ["Work:", "  n1", "  n2", "  n0", "n3", "n4"],
               "a loose note dropped high in the gap at a group's end joins the group as its last note")
    checkEqual(drop(id[4], after: id[2], upper: true, groups, notes), ["n0", "Work:", "  n1", "  n2", "  n4", "n3"],
               "a loose note from below joins a group at its end")
    check(groups.reorderPlan(moving: id[3], in: notes)?.result(at: 0, upper: true) == nil, "only the gap at a group's end has two halves")
    checkEqual(drop(id[2], after: id[4], groups, notes), ["n0", "Work:", "  n1", "n3", "n4", "n2"],
               "a note dragged out of a group leaves it")
    checkEqual(drop(id[1], after: id[2], upper: true, groups, notes), ["n0", "Work:", "  n2", "  n1", "n3", "n4"],
               "a note keeps its group when moved high into the group's end")
    checkEqual(drop(id[1], after: id[2], groups, notes), ["n0", "Work:", "  n2", "n1", "n3", "n4"],
               "a note moved low into the gap at its group's end leaves the group")
    check(groups.reorderPlan(moving: id[2], in: notes)?.startsUpper == true, "lifting a group's last note keeps it in the group")
    check(groups.reorderPlan(moving: id[3], in: notes)?.startsUpper == false, "lifting the loose note under a group keeps it loose")
    checkEqual(drop(work, after: id[4], groups, notes), ["n0", "n3", "n4", "Work:", "  n1", "  n2"],
               "a dragged group moves with all of its notes")
    checkEqual(drop(work, after: nil, groups, notes), ["Work:", "  n1", "  n2", "n0", "n3", "n4"],
               "a group can move to the top")

    var home = groups
    let homeID = home.create(name: "Home", with: id[3])
    home.add(id[4], to: homeID)
    check(drop(work, after: id[3], home, notes) == nil, "a group never lands inside another group")
    checkEqual(drop(homeID, after: id[0], home, notes), ["n0", "Home:", "  n3", "  n4", "Work:", "  n1", "  n2"],
               "groups swap places as blocks")

    notes[0].isPinned = true
    check(drop(id[3], after: nil, groups, notes) == nil, "an unpinned note never moves above a pinned one")
    checkEqual(drop(id[0], after: nil, groups, notes), ["n0", "Work:", "  n1", "  n2", "n3", "n4"],
               "a pinned note stays among the pinned ones")
    notes[0].isPinned = false

    var collapsed = groups
    collapsed.update(work) { $0.isCollapsed = true }
    let plan = collapsed.reorderPlan(moving: id[0], in: notes)
    checkEqual(plan?.into, [work], "a collapsed group takes a note dropped on its header")
    checkEqual(drop(id[0], after: work, collapsed, notes), ["Work+", "n0", "n3", "n4"],
               "a note dropped after a collapsed group stays loose below it")
    checkEqual(drop(work, after: id[4], collapsed, notes), ["n0", "n3", "n4", "Work+"],
               "a collapsed group moves with its hidden notes")
    let movedPlan = collapsed.reorderPlan(moving: work, in: notes)
    let moved = (0..<(movedPlan?.slotCount ?? 0)).lazy.compactMap { movedPlan?.result(at: $0, upper: false) }.first { $0.order.last == id[2] }
    check(moved?.order.suffix(2) == [id[1], id[2]], "hidden notes of a moved group keep their order")

    let forward = groups.reorderPlan(moving: id[0], in: notes)!
    let backward = groups.reorderPlan(moving: id[0], in: notes)!
    let ascending = (0..<forward.slotCount).flatMap { [forward.result(at: $0, upper: false), forward.result(at: $0, upper: true)] }
    let descending = (0..<backward.slotCount).reversed().flatMap { [backward.result(at: $0, upper: true), backward.result(at: $0, upper: false)] }
    checkEqual(ascending, Array(descending.reversed()), "a landing place gives the same result whatever order places are asked in")
    check(forward.result(at: forward.slotCount, upper: false) == nil && forward.result(at: -1, upper: false) == nil, "places outside the list are not landing places")

    var single = NoteGroups()
    let solo = single.create(name: "Solo", with: id[1])
    let leaving = single.reorderPlan(moving: id[1], in: notes)?.result(at: 0, upper: false)
    check(leaving?.groups.group(solo) == nil, "dragging the last note out of a group removes the group")
}
