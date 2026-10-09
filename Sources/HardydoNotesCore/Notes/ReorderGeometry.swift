import CoreGraphics
import Foundation

/// The drag math of a reorderable list along one axis: where each gap lies, and how far the other rows slide to open it.
public struct ReorderGeometry: Sendable {
    /// The rows left once the lifted block is taken out, in order.
    public let remaining: [UUID]
    public let leads: [UUID: CGFloat]
    public let lengths: [UUID: CGFloat]
    public let origin: CGFloat
    public let blockLead: CGFloat
    public let blockLength: CGFloat
    /// The gap the block was lifted from.
    public let startIndex: Int
    private let prefix: [CGFloat]

    /// Nil when a row has not been measured yet.
    public init?(rows: [UUID], block: [UUID], leads: [UUID: CGFloat], lengths: [UUID: CGFloat]) {
        guard rows.allSatisfy({ leads[$0] != nil && lengths[$0] != nil }), let first = rows.first, let blockFirst = block.first,
              let startIndex = rows.firstIndex(of: blockFirst), let origin = leads[first], let blockLead = leads[blockFirst]
        else { return nil }
        let lifted = Set(block)
        remaining = rows.filter { !lifted.contains($0) }
        prefix = remaining.reduce(into: [CGFloat(0)]) { sums, id in sums.append(sums[sums.count - 1] + lengths[id]!) }
        self.leads = leads
        self.lengths = lengths
        self.origin = origin
        self.blockLead = blockLead
        blockLength = block.reduce(0) { $0 + (lengths[$1] ?? 0) }
        self.startIndex = startIndex
    }

    public var slotCount: Int { prefix.count }

    public func slotCenter(_ index: Int) -> CGFloat {
        origin + prefix[index] + blockLength / 2
    }

    /// How far the block moves from where it started to sit in the gap at `index`.
    public func landingOffset(_ index: Int) -> CGFloat {
        origin + prefix[index] - blockLead
    }

    /// The block stays within the list, from above its first row to below its last.
    public func clamped(_ translation: CGFloat) -> CGFloat {
        min(max(translation, origin - blockLead), origin + prefix[prefix.count - 1] - blockLead)
    }

    /// How far each remaining row slides so the gap at `index` opens; rows that stay put are left out.
    public func shifts(forGapAt index: Int) -> [UUID: CGFloat] {
        var shifts: [UUID: CGFloat] = [:]
        var position = origin
        for (offset, id) in remaining.enumerated() {
            if offset == index { position += blockLength }
            let shift = position - (leads[id] ?? position)
            if shift != 0 { shifts[id] = shift }
            position += lengths[id] ?? 0
        }
        return shifts
    }

    /// The valid gap whose middle is closest to `center`, found by walking out from the closest gap of all.
    public func nearestSlot(to center: CGFloat, where isValid: (Int) -> Bool) -> Int? {
        var low = 0
        var high = slotCount
        while low < high {
            let middle = (low + high) / 2
            if slotCenter(middle) <= center { low = middle + 1 } else { high = middle }
        }
        var down = low - 1
        var up = low
        while down >= 0 || up < slotCount {
            let takesDown = up >= slotCount || (down >= 0 && center - slotCenter(down) <= slotCenter(up) - center)
            let index = takesDown ? down : up
            if isValid(index) { return index }
            if takesDown { down -= 1 } else { up += 1 }
        }
        return nil
    }

    /// The row whose span holds `position`, such as the row a file is dropped on.
    public static func row(at position: CGFloat, leads: [UUID: CGFloat], lengths: [UUID: CGFloat]) -> UUID? {
        leads.first { id, lead in position >= lead && position < lead + (lengths[id] ?? 0) }?.key
    }
}
