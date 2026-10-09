import CoreGraphics
import Foundation

public enum ReorderDrop: Hashable, Sendable {
    /// `upper` is the upper half of a gap whose halves land differently, such as the end of a sidebar group.
    case slot(Int, upper: Bool)
    case into(UUID)

    public var index: Int? {
        if case .slot(let index, _) = self { index } else { nil }
    }
}

/// Where a dragged block would drop as the pointer carries it: a gap, one half of a gap, or a collapsed group.
public struct ReorderTracker {
    public let geometry: ReorderGeometry
    public private(set) var drop: ReorderDrop
    /// How far each other row slides to open the gap the block would drop into.
    public private(set) var shifts: [UUID: CGFloat] = [:]
    private let into: Set<UUID>
    private let isSlot: (Int, Bool) -> Bool
    private var anchor: CGFloat = 0

    /// How far the pointer must travel from where the drop last changed gaps before it may change again.
    public static let hysteresis: CGFloat = 16
    /// How far past a two-halved gap's middle the pointer must go before the drop switches halves.
    public static let halfMargin: CGFloat = 4

    /// `isSlot` tells whether the gap at an index, or its upper half when the flag is set, is a place the block may land.
    public init(geometry: ReorderGeometry, start: ReorderDrop, into: Set<UUID> = [], isSlot: @escaping (Int, Bool) -> Bool) {
        self.geometry = geometry
        drop = start
        self.into = into
        self.isSlot = isSlot
    }

    /*
     Takes how far the pointer has carried the block from where it started, unclamped: the gap after a group that
     ends the list has a lower half only a pointer beyond the list's end reaches. True when the drop changed.
     */
    public mutating func move(to value: CGFloat) -> Bool {
        let center = geometry.blockLead + value + geometry.blockLength / 2
        guard let next = drop(at: center, moved: value), next != drop else { return false }
        var nextShifts = shifts
        if let index = next.index, index != drop.index {
            nextShifts = geometry.shifts(forGapAt: index)
            guard !movesAway(nextShifts, before: center) else { return false }
            anchor = value
        }
        drop = next
        shifts = nextShifts
        return true
    }

    /// How far the block moves to sit where it drops; a drop onto a group keeps the offset of the last gap.
    public func landingOffset(keeping current: CGFloat?) -> CGFloat {
        drop.index.map(geometry.landingOffset) ?? current ?? 0
    }

    private func drop(at center: CGFloat, moved value: CGFloat) -> ReorderDrop? {
        if let group = into.first(where: { isOver($0, at: center) }) { return .into(group) }
        let index: Int
        if let current = drop.index, abs(value - anchor) < Self.hysteresis {
            index = current
        } else {
            guard let nearest = geometry.nearestSlot(to: center, where: { isSlot($0, false) || isSlot($0, true) }) else { return nil }
            index = nearest
        }
        switch (isSlot(index, false), isSlot(index, true)) {
        case (true, false): return .slot(index, upper: false)
        case (false, true): return .slot(index, upper: true)
        case (false, false): return drop
        case (true, true):
            let offset = center - geometry.slotCenter(index)
            if case .slot(index, let upper) = drop, abs(offset) <= Self.halfMargin { return .slot(index, upper: upper) }
            return .slot(index, upper: offset < 0)
        }
    }

    // A collapsed group's header must not slide out from under a note heading for it before the note can be dropped on it.
    private func movesAway(_ next: [UUID: CGFloat], before center: CGFloat) -> Bool {
        into.contains { id in
            guard let lead = geometry.leads[id], let length = geometry.lengths[id] else { return false }
            let now = shifts[id] ?? 0
            let then = next[id] ?? 0
            let top = lead + now
            if then < now { return center <= top + length * 0.75 }
            if then > now { return center >= top + length * 0.25 }
            return false
        }
    }

    // The middle half of a collapsed group's header takes the note in, as dropping on a closed folder does.
    private func isOver(_ id: UUID, at center: CGFloat) -> Bool {
        guard let lead = geometry.leads[id], let length = geometry.lengths[id] else { return false }
        let top = lead + (shifts[id] ?? 0)
        return center > top + length * 0.25 && center < top + length * 0.75
    }
}
