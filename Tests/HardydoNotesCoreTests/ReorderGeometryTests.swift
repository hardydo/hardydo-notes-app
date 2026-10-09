import CoreGraphics
import Foundation
import HardydoNotesCore
import Testing

private func rows() -> (ids: [UUID], leads: [UUID: CGFloat], lengths: [UUID: CGFloat]) {
    let ids = (0..<5).map { _ in UUID() }
    let leads = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, CGFloat($0) * 10) })
    let lengths = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGFloat(10)) })
    return (ids, leads, lengths)
}

private func singleRowBlock(_ ids: [UUID], _ leads: [UUID: CGFloat], _ lengths: [UUID: CGFloat]) -> ReorderGeometry {
    ReorderGeometry(rows: ids, block: [ids[1]], leads: leads, lengths: lengths)!
}

@Suite struct ReorderGeometryTests {
    @Test func singleRowBlockGeometry() {
        let (ids, leads, lengths) = rows()
        let single = singleRowBlock(ids, leads, lengths)
        #expect(single.startIndex == 1, "the block starts in the gap it was lifted from")
        #expect(single.slotCount == 5, "four remaining rows leave five gaps")
        #expect(single.shifts(forGapAt: 1) == [:], "opening the gap the block came from moves nothing")
        #expect(single.shifts(forGapAt: 3) == [ids[2]: -10, ids[3]: -10], "rows between the start and the gap slide up by the block")
        #expect(single.shifts(forGapAt: 0) == [ids[0]: 10], "rows above the gap slide down by the block")
        #expect(single.landingOffset(3) == 20, "the block lands two rows lower")
    }

    @Test func multiRowBlockGeometry() {
        let (ids, leads, lengths) = rows()
        let block = ReorderGeometry(rows: ids, block: Array(ids[1...3]), leads: leads, lengths: lengths)!
        #expect(block.slotCount == 3, "a lifted block of three leaves three gaps")
        #expect(block.shifts(forGapAt: 2) == [ids[4]: -30], "a row below slides up by the whole block")
        #expect(block.shifts(forGapAt: 0) == [ids[0]: 30], "a row above slides down by the whole block")
    }

    @Test func blockIsClampedToTheList() {
        let (ids, leads, lengths) = rows()
        let single = singleRowBlock(ids, leads, lengths)
        #expect(single.clamped(-100) == -10, "the block cannot go above the list")
        #expect(single.clamped(100) == 30, "the block cannot go below the list")
        #expect(single.clamped(12) == 12, "inside the list the block follows the pointer")
    }

    @Test func nearestSlotSkipsInvalidGaps() {
        let (ids, leads, lengths) = rows()
        let single = singleRowBlock(ids, leads, lengths)
        #expect(single.nearestSlot(to: 26, where: { _ in true }) == 2, "the gap whose middle is closest is chosen")
        #expect(single.nearestSlot(to: 26, where: { $0 != 2 }) == 3, "an invalid gap is skipped for the next closest")
        #expect(single.nearestSlot(to: -50, where: { $0 >= 3 }) == 3, "the walk goes past every invalid gap")
        #expect(single.nearestSlot(to: 26, where: { _ in false }) == nil, "no valid gap gives nothing")
    }

    @Test func rowLookupByPoint() {
        let (ids, leads, lengths) = rows()
        #expect(ReorderGeometry.row(at: 15, leads: leads, lengths: lengths) == ids[1], "a point inside a row finds that row")
        #expect(ReorderGeometry.row(at: 20, leads: leads, lengths: lengths) == ids[2], "a point on a boundary belongs to the row below it")
        #expect(ReorderGeometry.row(at: -1, leads: leads, lengths: lengths) == nil, "a point above every row finds none")
        #expect(ReorderGeometry.row(at: 50, leads: leads, lengths: lengths) == nil, "a point below every row finds none")
        #expect(ReorderGeometry(rows: ids, block: [ids[0]], leads: [:], lengths: lengths) == nil, "rows that were never measured give no geometry")
    }

    @Test func tabSlotRangesRespectPinnedTabs() {
        let ids = (0..<5).map { _ in UUID() }
        var tabs = TabList(ids: ids, active: ids[0], pinned: [ids[0], ids[1]])
        #expect(tabs.slotRange(moving: ids[0]) == 0...1, "a pinned tab lands only among the pinned tabs")
        #expect(tabs.slotRange(moving: ids[3]) == 2...4, "an unpinned tab lands only after the pinned tabs")
        #expect(tabs.slotRange(moving: UUID()) == nil, "a tab that is not open has no places")
        var moved = Array(ids.filter { $0 != ids[3] })
        moved.insert(ids[3], at: 2)
        tabs.reorder(moved)
        #expect(tabs.ids == moved, "the first place in the range is one reorder accepts")
    }
}
