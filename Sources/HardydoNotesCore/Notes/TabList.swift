import Foundation

/*
 Open tabs like VS Code: single clicks reuse one preview tab; editing or opening to keep gives a tab of its own.
 Pinned tabs stay first and survive the bulk close commands.
 */
public struct TabList: Equatable, Sendable {
    public private(set) var ids: [UUID] = []
    public private(set) var preview: UUID?
    public private(set) var active: UUID?
    public private(set) var pinnedCount = 0
    private var closed: [ClosedTab] = []
    private static let closedLimit = 20

    private struct ClosedTab: Equatable, Sendable {
        let id: UUID
        let index: Int
        let wasPinned: Bool
    }

    public init(ids: [UUID] = [], active: UUID? = nil, pinned: Set<UUID> = []) {
        self.ids = ids.filter(pinned.contains) + ids.filter { !pinned.contains($0) }
        pinnedCount = self.ids.count { pinned.contains($0) }
        self.active = active.flatMap { ids.contains($0) ? $0 : nil } ?? self.ids.first
    }

    public var pinned: [UUID] { Array(ids.prefix(pinnedCount)) }

    public func isPinned(_ id: UUID) -> Bool {
        ids.prefix(pinnedCount).contains(id)
    }

    public var canReopen: Bool { !closed.isEmpty }

    public mutating func open(_ id: UUID, keep: Bool) {
        if !ids.contains(id) {
            let current = active.flatMap { ids.firstIndex(of: $0) }
            if !keep, let preview, let index = ids.firstIndex(of: preview) {
                ids[index] = id
            } else {
                ids.insert(id, at: max(current.map { $0 + 1 } ?? ids.count, pinnedCount))
            }
            if !keep { preview = id }
        }
        if keep, preview == id { preview = nil }
        active = id
    }

    public mutating func activate(_ id: UUID) {
        guard ids.contains(id) else { return }
        active = id
    }

    public mutating func activate(at index: Int) {
        guard ids.indices.contains(index) else { return }
        active = ids[index]
    }

    public mutating func keep(_ id: UUID) {
        if preview == id { preview = nil }
    }

    public mutating func pin(_ id: UUID) {
        guard let index = ids.firstIndex(of: id), index >= pinnedCount else { return }
        ids.insert(ids.remove(at: index), at: pinnedCount)
        pinnedCount += 1
        keep(id)
    }

    public mutating func unpin(_ id: UUID) {
        guard let index = ids.firstIndex(of: id), index < pinnedCount else { return }
        pinnedCount -= 1
        ids.insert(ids.remove(at: index), at: pinnedCount)
    }

    /// Closing the active tab activates the one to its right, else the one to its left.
    public mutating func close(_ id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        closed.append(ClosedTab(id: id, index: index, wasPinned: index < pinnedCount))
        if closed.count > Self.closedLimit { closed.removeFirst() }
        remove(at: index)
    }

    public func canCloseOthers(_ id: UUID) -> Bool {
        ids.dropFirst(pinnedCount).contains { $0 != id }
    }

    public func canCloseRight(of id: UUID) -> Bool {
        guard let index = ids.firstIndex(of: id) else { return false }
        return max(index + 1, pinnedCount) < ids.count
    }

    public var canCloseAll: Bool { ids.count > pinnedCount }

    public mutating func closeOthers(_ id: UUID) {
        guard ids.contains(id) else { return }
        for other in ids.dropFirst(pinnedCount) where other != id { close(other) }
        active = id
    }

    public mutating func closeRight(of id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        let closing = ids[max(index + 1, pinnedCount)...]
        let activeClosing = active.map(closing.contains) ?? false
        for other in closing.reversed() { close(other) }
        if activeClosing { active = id }
    }

    public mutating func closeAll() {
        for id in ids.dropFirst(pinnedCount).reversed() { close(id) }
    }

    /// Brings back the most recently closed tab whose note still exists, where it was.
    @discardableResult
    public mutating func reopen(existing: Set<UUID>) -> UUID? {
        while let last = closed.popLast() {
            guard existing.contains(last.id), !ids.contains(last.id) else { continue }
            let index = last.wasPinned ? min(last.index, pinnedCount) : min(max(last.index, pinnedCount), ids.count)
            ids.insert(last.id, at: index)
            if last.wasPinned { pinnedCount += 1 }
            active = last.id
            return last.id
        }
        return nil
    }

    /// Applies an order worked out while dragging, as long as it keeps the same tabs and pinned ones first.
    public mutating func reorder(_ order: [UUID]) {
        guard order.count == ids.count, Set(order) == Set(ids), Set(order.prefix(pinnedCount)) == Set(pinned) else { return }
        ids = order
    }

    public mutating func cycle(by offset: Int) {
        guard !ids.isEmpty else { return }
        let current = active.flatMap { ids.firstIndex(of: $0) } ?? 0
        active = ids[((current + offset) % ids.count + ids.count) % ids.count]
    }

    /// Drops tabs whose notes are gone (deleted, or a file closed); they cannot be reopened.
    public mutating func prune(keeping existing: Set<UUID>) {
        for (index, id) in ids.enumerated().reversed() where !existing.contains(id) {
            remove(at: index)
        }
        closed.removeAll { !existing.contains($0.id) }
    }

    private mutating func remove(at index: Int) {
        let id = ids.remove(at: index)
        if index < pinnedCount { pinnedCount -= 1 }
        if preview == id { preview = nil }
        if active == id { active = ids.isEmpty ? nil : ids[min(index, ids.count - 1)] }
    }
}
