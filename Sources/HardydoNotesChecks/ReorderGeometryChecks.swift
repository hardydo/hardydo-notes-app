import CoreGraphics
import Foundation
import HardydoNotesCore

func runReorderGeometryChecks() {
    let ids = (0..<5).map { _ in UUID() }
    let leads = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, CGFloat($0) * 10) })
    let lengths = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGFloat(10)) })

    let single = ReorderGeometry(rows: ids, block: [ids[1]], leads: leads, lengths: lengths)!
    checkEqual(single.startIndex, 1, "the block starts in the gap it was lifted from")
    checkEqual(single.slotCount, 5, "four remaining rows leave five gaps")
    checkEqual(single.shifts(forGapAt: 1), [:], "opening the gap the block came from moves nothing")
    checkEqual(single.shifts(forGapAt: 3), [ids[2]: -10, ids[3]: -10], "rows between the start and the gap slide up by the block")
    checkEqual(single.shifts(forGapAt: 0), [ids[0]: 10], "rows above the gap slide down by the block")
    checkEqual(single.landingOffset(3), 20, "the block lands two rows lower")

    let block = ReorderGeometry(rows: ids, block: Array(ids[1...3]), leads: leads, lengths: lengths)!
    checkEqual(block.slotCount, 3, "a lifted block of three leaves three gaps")
    checkEqual(block.shifts(forGapAt: 2), [ids[4]: -30], "a row below slides up by the whole block")
    checkEqual(block.shifts(forGapAt: 0), [ids[0]: 30], "a row above slides down by the whole block")

    checkEqual(single.clamped(-100), -10, "the block cannot go above the list")
    checkEqual(single.clamped(100), 30, "the block cannot go below the list")
    checkEqual(single.clamped(12), 12, "inside the list the block follows the pointer")

    checkEqual(single.nearestSlot(to: 26, where: { _ in true }), 2, "the gap whose middle is closest is chosen")
    checkEqual(single.nearestSlot(to: 26, where: { $0 != 2 }), 3, "an invalid gap is skipped for the next closest")
    checkEqual(single.nearestSlot(to: -50, where: { $0 >= 3 }), 3, "the walk goes past every invalid gap")
    check(single.nearestSlot(to: 26, where: { _ in false }) == nil, "no valid gap gives nothing")

    checkEqual(ReorderGeometry.row(at: 15, leads: leads, lengths: lengths), ids[1], "a point inside a row finds that row")
    checkEqual(ReorderGeometry.row(at: 20, leads: leads, lengths: lengths), ids[2], "a point on a boundary belongs to the row below it")
    check(ReorderGeometry.row(at: -1, leads: leads, lengths: lengths) == nil, "a point above every row finds none")
    check(ReorderGeometry.row(at: 50, leads: leads, lengths: lengths) == nil, "a point below every row finds none")
    check(ReorderGeometry(rows: ids, block: [ids[0]], leads: [:], lengths: lengths) == nil, "rows that were never measured give no geometry")

    var tabs = TabList(ids: ids, active: ids[0], pinned: [ids[0], ids[1]])
    checkEqual(tabs.slotRange(moving: ids[0]), 0...1, "a pinned tab lands only among the pinned tabs")
    checkEqual(tabs.slotRange(moving: ids[3]), 2...4, "an unpinned tab lands only after the pinned tabs")
    check(tabs.slotRange(moving: UUID()) == nil, "a tab that is not open has no places")
    var moved = Array(ids.filter { $0 != ids[3] })
    moved.insert(ids[3], at: 2)
    tabs.reorder(moved)
    checkEqual(tabs.ids, moved, "the first place in the range is one reorder accepts")
}
