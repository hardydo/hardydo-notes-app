import CoreGraphics
import Foundation
import HardydoNotesCore
import Testing

/// A sidebar of notes 49 pt and group headers 35 pt tall, laid end to end from 0, as the app measures it.
private struct Sidebar {
    var notes: [Note]
    var groups = NoteGroups()
    var ids: [UUID] { notes.map(\.id) }

    init(count: Int) {
        notes = (0..<count).map { Note(body: "n\($0)") }
    }

    mutating func group(_ name: String, _ members: [Int]) -> NoteGroup.ID {
        let group = groups.create(name: name, with: ids[members[0]])
        for member in members.dropFirst() { groups.add(ids[member], to: group) }
        return group
    }

    func plan(lifting id: UUID) -> SidebarReorderPlan {
        groups.reorderPlan(moving: id, in: notes)!
    }

    func tracker(lifting id: UUID) -> ReorderTracker {
        let plan = plan(lifting: id)
        var leads: [UUID: CGFloat] = [:]
        var lengths: [UUID: CGFloat] = [:]
        var position: CGFloat = 0
        for row in groups.rows(for: notes) {
            let length: CGFloat = if case .header = row { 35 } else { 49 }
            leads[row.id] = position
            lengths[row.id] = length
            position += length
        }
        let geometry = ReorderGeometry(rows: plan.rows, block: plan.block, leads: leads, lengths: lengths)!
        return ReorderTracker(geometry: geometry, start: .slot(geometry.startIndex, upper: plan.startsUpper), into: plan.into) {
            plan.result(at: $0, upper: $1) != nil
        }
    }

    /// Every place the block may land, by the plan.
    func places(lifting id: UUID) -> Set<ReorderDrop> {
        let plan = plan(lifting: id)
        var places: Set<ReorderDrop> = []
        for index in 0..<plan.slotCount {
            for upper in [false, true] where plan.result(at: index, upper: upper) != nil { places.insert(.slot(index, upper: upper)) }
        }
        return places.union(plan.into.map { .into($0) })
    }

    /// Every drop seen while the pointer moves a point at a time from rest to `limit`.
    func sweep(lifting id: UUID, to limit: CGFloat) -> [ReorderDrop] {
        var tracker = tracker(lifting: id)
        var seen = [tracker.drop]
        for step in 1...Int(abs(limit)) {
            if tracker.move(to: CGFloat(step) * (limit < 0 ? -1 : 1)) { seen.append(tracker.drop) }
        }
        return seen
    }

    /// N0 N1 [G1: N2 N3] N4 N5 [G2: N6 N7]: a group in the middle and one that ends the list.
    static func middleAndEnd() -> (Sidebar, first: NoteGroup.ID, last: NoteGroup.ID) {
        var sidebar = Sidebar(count: 8)
        let first = sidebar.group("G1", [2, 3])
        let last = sidebar.group("G2", [6, 7])
        return (sidebar, first, last)
    }

    /// [G1: N0 N1] N2 N3 N4 N5 [G2: N6 N7]: a group first.
    static func groupFirst() -> Sidebar {
        var sidebar = Sidebar(count: 8)
        _ = sidebar.group("G1", [0, 1])
        _ = sidebar.group("G2", [6, 7])
        return sidebar
    }
}

@Suite struct ReorderTrackerTests {
    @Test func everyPlaceIsReachableWithAGroupInTheMiddleAndAtTheEnd() {
        let (sidebar, first, last) = Sidebar.middleAndEnd()
        for id in sidebar.ids + [first, last] {
            let places = sidebar.places(lifting: id)
            let reached = Set(sidebar.sweep(lifting: id, to: -700) + sidebar.sweep(lifting: id, to: 700))
            #expect(reached == places, "every place, and only those, is reached lifting \(id)")
        }
    }

    @Test func everyPlaceIsReachableWithAGroupFirst() {
        let sidebar = Sidebar.groupFirst()
        for id in sidebar.ids {
            let reached = Set(sidebar.sweep(lifting: id, to: -700) + sidebar.sweep(lifting: id, to: 700))
            #expect(reached == sidebar.places(lifting: id), "every place is reached lifting a note")
        }
    }

    @Test func aPointerPastTheListsEndLeavesTheGroupThatEndsIt() {
        let (sidebar, _, _) = Sidebar.middleAndEnd()
        var tracker = sidebar.tracker(lifting: sidebar.ids[0])
        let end = tracker.geometry.slotCount - 1
        let restingAtEnd = tracker.geometry.landingOffset(end)
        for step in 1...Int(restingAtEnd) { _ = tracker.move(to: CGFloat(step)) }
        #expect(tracker.drop == .slot(end, upper: true), "coming down, the row first joins the last group")
        _ = tracker.move(to: restingAtEnd + ReorderTracker.halfMargin + 1)
        #expect(tracker.drop == .slot(end, upper: false), "a pointer just past where the row stops leaves the group")
    }

    @Test func halvesSwitchOnlyPastTheMargin() {
        let (sidebar, _, _) = Sidebar.middleAndEnd()
        var tracker = sidebar.tracker(lifting: sidebar.ids[0])
        let end = tracker.geometry.slotCount - 1
        let middle = tracker.geometry.landingOffset(end)
        for step in 1...Int(middle + 10) { _ = tracker.move(to: CGFloat(step)) }
        #expect(tracker.drop == .slot(end, upper: false))
        _ = tracker.move(to: middle - ReorderTracker.halfMargin + 1)
        #expect(tracker.drop == .slot(end, upper: false), "inside the margin the lower half holds")
        _ = tracker.move(to: middle - ReorderTracker.halfMargin - 1)
        #expect(tracker.drop == .slot(end, upper: true), "past the margin the upper half takes over")
    }

    @Test func aGapHoldsUntilThePointerTravelsPastTheHysteresis() {
        let (sidebar, _, _) = Sidebar.middleAndEnd()
        var tracker = sidebar.tracker(lifting: sidebar.ids[0])
        var changedAt: CGFloat = 0
        for step in 1...200 where tracker.move(to: CGFloat(step)) {
            changedAt = CGFloat(step)
            break
        }
        let held = tracker.drop
        #expect(changedAt > 0 && held != .slot(0, upper: false), "moving down leaves the first gap")
        _ = tracker.move(to: changedAt - ReorderTracker.hysteresis + 1)
        #expect(tracker.drop == held, "a small move back keeps the gap")
        _ = tracker.move(to: 0)
        #expect(tracker.drop == .slot(0, upper: false), "a move back past the hysteresis returns to the first gap")
    }

    @Test func theMiddleOfACollapsedHeaderTakesTheNoteIn() {
        var (sidebar, first, _) = Sidebar.middleAndEnd()
        sidebar.groups.update(first) { $0.isCollapsed = true }
        let down = sidebar.sweep(lifting: sidebar.ids[0], to: 300)
        #expect(down.contains(.into(first)), "a note moving down drops onto the collapsed group")
        let up = sidebar.sweep(lifting: sidebar.ids[4], to: -300)
        #expect(up.contains(.into(first)), "a note moving up drops onto the collapsed group")
        let open = Sidebar.middleAndEnd().0
        #expect(!open.sweep(lifting: open.ids[0], to: 300).contains { if case .into = $0 { true } else { false } }, "an open group is never a drop target")
    }

    @Test func aCollapsedHeaderDoesNotSlideAwayFromANoteHeadingForIt() {
        var (sidebar, first, _) = Sidebar.middleAndEnd()
        sidebar.groups.update(first) { $0.isCollapsed = true }
        let down = sidebar.sweep(lifting: sidebar.ids[0], to: 300)
        let target = down.firstIndex(of: .into(first))!
        let beforeHeader = sidebar.tracker(lifting: sidebar.ids[0]).geometry.remaining.firstIndex(of: first)!
        #expect(!down[..<target].contains { ($0.index ?? 0) > beforeHeader }, "the gap past the header is not taken before the note reaches it")
    }

    @Test func aGroupsLastNoteStartsInTheGroup() {
        let (sidebar, _, _) = Sidebar.middleAndEnd()
        var tracker = sidebar.tracker(lifting: sidebar.ids[7])
        #expect(tracker.drop.index != nil && tracker.drop == .slot(tracker.drop.index!, upper: true))
        _ = tracker.move(to: 2)
        #expect(tracker.drop == .slot(tracker.geometry.startIndex, upper: true), "a small move keeps it in its group")
    }

    @Test func aGroupNeverLandsInsideAnotherGroup() {
        let (sidebar, first, last) = Sidebar.middleAndEnd()
        for group in [first, last] {
            let reached = Set(sidebar.sweep(lifting: group, to: -700) + sidebar.sweep(lifting: group, to: 700))
            #expect(reached.isSubset(of: sidebar.places(lifting: group)), "a dragged group only reaches gaps between groups and loose notes")
        }
    }

    @Test func landingFollowsTheGapAndKeepsItOverAGroup() {
        var (sidebar, first, _) = Sidebar.middleAndEnd()
        var tracker = sidebar.tracker(lifting: sidebar.ids[0])
        _ = tracker.move(to: 60)
        #expect(tracker.landingOffset(keeping: nil) == tracker.geometry.landingOffset(tracker.drop.index!))
        sidebar.groups.update(first) { $0.isCollapsed = true }
        var into = sidebar.tracker(lifting: sidebar.ids[0])
        for step in 1...300 where into.drop != .into(first) { _ = into.move(to: CGFloat(step)) }
        #expect(into.drop == .into(first))
        #expect(into.landingOffset(keeping: 42) == 42, "over a group the last gap's offset is kept")
    }
}
