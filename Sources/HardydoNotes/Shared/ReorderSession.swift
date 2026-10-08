import SwiftUI

enum ReorderDrop: Equatable {
    /// `upper` is the upper half of a gap whose halves land differently, such as the end of a sidebar group.
    case slot(Int, upper: Bool)
    case into(UUID)

    var index: Int? {
        if case .slot(let index, _) = self { index } else { nil }
    }
}

/// Where a lifted row would land: how far from where it started, and the lane (a sidebar group) it would join.
struct ReorderLanding: Equatable {
    let offset: CGFloat
    let lane: UUID?
}

/// What a press on a row may move: the rows of its list, the block that lifts, where it may land.
struct ReorderPlan {
    let rows: [UUID]
    let block: [UUID]
    let slots: Set<Int>
    var upperSlots: Set<Int> = []
    var startsUpper = false
    var into: Set<UUID> = []
    var lane: (ReorderDrop) -> UUID? = { _ in nil }
    let commit: (ReorderDrop) -> Void
}

/*
 Reordering the way Chromium drags tabs: the pressed view itself follows the pointer while the others slide
 aside, and nothing in the model changes until the rows have settled where the new order puts them. Rows only
 ever move by their offsets, so anything drawn from their positions (the sidebar's group bars) moves with them.
 */
@MainActor
@Observable
final class ReorderSession {
    let axis: Axis
    let space: String
    private(set) var lifted: [UUID] = []
    private(set) var translation: CGFloat = 0
    private(set) var shifts: [UUID: CGFloat] = [:]
    private(set) var target: UUID?
    /// Set from the start of a drag until its drop is committed; a drop onto a collapsed group keeps the last gap's offset.
    private(set) var landing: ReorderLanding?
    private(set) var isSinking = false
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    @ObservationIgnored private var press: Press?
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var settling: Drag?

    private static let startDistance: CGFloat = 4
    private static let hysteresis: CGFloat = 16
    /// How far past a two-halved gap's middle the pointer must go before the drop switches halves.
    private static let halfMargin: CGFloat = 4
    private static let settle = Animation.easeOut(duration: 0.2)

    private struct Press {
        let id: UUID
        var moved = false
        var refused = false
    }

    private struct Drag {
        let plan: ReorderPlan
        let remaining: [UUID]
        let leads: [UUID: CGFloat]
        let lengths: [UUID: CGFloat]
        let prefix: [CGFloat]
        let origin: CGFloat
        let blockLead: CGFloat
        let blockLength: CGFloat
        var drop: ReorderDrop
        var anchor: CGFloat = 0
    }

    init(axis: Axis, space: String) {
        self.axis = axis
        self.space = space
    }

    var isDragging: Bool { drag != nil }

    func update(_ id: UUID, translation: CGSize, onPress: () -> Void, plan: () -> ReorderPlan?) {
        if press?.id != id {
            commitSettling()
            press = Press(id: id)
            onPress()
        }
        let distance = hypot(translation.width, translation.height)
        if distance >= Self.startDistance { press?.moved = true }
        if drag == nil {
            guard distance >= Self.startDistance, press?.refused == false else { return }
            guard let plan = plan(), let started = start(plan) else {
                press?.refused = true
                return
            }
            drag = started
            lifted = plan.block
            landing = Self.landing(started.drop, in: started, keeping: nil)
        }
        move(axis == .vertical ? translation.height : translation.width)
    }

    /// Ends the press; true when it was a click rather than a drag.
    func end() -> Bool {
        defer { press = nil }
        guard let drag else { return press?.moved == false }
        self.drag = nil
        settling = drag
        withAnimation(Self.settle) {
            switch drag.drop {
            case .slot:
                translation = landing?.offset ?? 0
            case .into(let group):
                shifts = Self.shifts(for: drag.remaining.count, in: drag)
                translation = (drag.leads[group] ?? 0) + (shifts[group] ?? 0) - drag.blockLead
                isSinking = true
            }
        } completion: { [weak self] in
            self?.commitSettling()
        }
        return false
    }

    // Every row already shows where the new order puts it, so the model catches up without anything moving.
    private func commitSettling() {
        guard let drag = settling else { return }
        settling = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag.plan.commit(drag.drop)
            translation = 0
            shifts = [:]
            target = nil
            landing = nil
            isSinking = false
        }
        withAnimation(.easeOut(duration: 0.12)) { lifted = [] }
    }

    private func start(_ plan: ReorderPlan) -> Drag? {
        var leads: [UUID: CGFloat] = [:]
        var lengths: [UUID: CGFloat] = [:]
        for id in plan.rows {
            guard let frame = frames[id] else { return nil }
            leads[id] = axis == .vertical ? frame.minY : frame.minX
            lengths[id] = axis == .vertical ? frame.height : frame.width
        }
        let block = Set(plan.block)
        guard let first = plan.rows.first, let blockFirst = plan.block.first,
              let start = plan.rows.firstIndex(of: blockFirst), let origin = leads[first], let blockLead = leads[blockFirst]
        else { return nil }
        let remaining = plan.rows.filter { !block.contains($0) }
        let prefix = remaining.reduce(into: [CGFloat(0)]) { sums, id in sums.append(sums[sums.count - 1] + (lengths[id] ?? 0)) }
        return Drag(
            plan: plan, remaining: remaining, leads: leads, lengths: lengths, prefix: prefix, origin: origin,
            blockLead: blockLead, blockLength: plan.block.reduce(0) { $0 + (lengths[$1] ?? 0) },
            drop: .slot(start, upper: plan.startsUpper)
        )
    }

    private func move(_ value: CGFloat) {
        guard var drag else { return }
        translation = value
        let center = drag.blockLead + value + drag.blockLength / 2
        guard let next = drop(at: center, moved: value, in: drag), next != drag.drop else { return }
        var nextShifts = shifts
        if let index = next.index, index != drag.drop.index {
            nextShifts = Self.shifts(for: index, in: drag)
            guard !movesAway(nextShifts, before: center, in: drag) else { return }
            drag.anchor = value
        }
        drag.drop = next
        self.drag = drag
        withAnimation(Self.settle) {
            shifts = nextShifts
            if case .into(let group) = next { target = group } else { target = nil }
            landing = Self.landing(next, in: drag, keeping: landing)
        }
    }

    private func drop(at center: CGFloat, moved value: CGFloat, in drag: Drag) -> ReorderDrop? {
        let plan = drag.plan
        if let group = plan.into.first(where: { isOver($0, at: center, in: drag) }) { return .into(group) }
        let index: Int
        if let current = drag.drop.index, abs(value - drag.anchor) < Self.hysteresis {
            index = current
        } else {
            let candidates = plan.slots.union(plan.upperSlots)
            guard let nearest = candidates.min(by: { abs(slotCenter($0, drag) - center) < abs(slotCenter($1, drag) - center) })
            else { return nil }
            index = nearest
        }
        switch (plan.slots.contains(index), plan.upperSlots.contains(index)) {
        case (true, false): return .slot(index, upper: false)
        case (false, true): return .slot(index, upper: true)
        case (false, false): return drag.drop
        case (true, true):
            let offset = center - slotCenter(index, drag)
            if case .slot(index, let upper) = drag.drop, abs(offset) <= Self.halfMargin { return .slot(index, upper: upper) }
            return .slot(index, upper: offset < 0)
        }
    }

    // A collapsed group's header must not slide out from under a note heading for it before the note can be dropped on it.
    private func movesAway(_ next: [UUID: CGFloat], before center: CGFloat, in drag: Drag) -> Bool {
        drag.plan.into.contains { id in
            guard let lead = drag.leads[id], let length = drag.lengths[id] else { return false }
            let now = shifts[id] ?? 0
            let then = next[id] ?? 0
            let top = lead + now
            if then < now { return center <= top + length * 0.75 }
            if then > now { return center >= top + length * 0.25 }
            return false
        }
    }

    private func slotCenter(_ index: Int, _ drag: Drag) -> CGFloat {
        drag.origin + drag.prefix[index] + drag.blockLength / 2
    }

    // The middle half of a collapsed group's header takes the note in, as dropping on a closed folder does.
    private func isOver(_ id: UUID, at center: CGFloat, in drag: Drag) -> Bool {
        guard let lead = drag.leads[id], let length = drag.lengths[id] else { return false }
        let top = lead + (shifts[id] ?? 0)
        return center > top + length * 0.25 && center < top + length * 0.75
    }

    private static func landing(_ drop: ReorderDrop, in drag: Drag, keeping current: ReorderLanding?) -> ReorderLanding {
        let offset = drop.index.map { drag.origin + drag.prefix[$0] - drag.blockLead } ?? current?.offset ?? 0
        return ReorderLanding(offset: offset, lane: drag.plan.lane(drop))
    }

    private static func shifts(for index: Int, in drag: Drag) -> [UUID: CGFloat] {
        var shifts: [UUID: CGFloat] = [:]
        var position = drag.origin
        for (offset, id) in drag.remaining.enumerated() {
            if offset == index { position += drag.blockLength }
            let shift = position - (drag.leads[id] ?? position)
            if shift != 0 { shifts[id] = shift }
            position += drag.lengths[id] ?? 0
        }
        return shifts
    }
}

extension View {
    /// Lets the view be pressed and dragged to a new place in its list; `onClick` gets the click count.
    func reorderable(
        _ id: UUID, in session: ReorderSession, cornerRadius: CGFloat = 7, liftedFill: Color = Color(nsColor: .windowBackgroundColor),
        plan: @escaping () -> ReorderPlan?, onPress: @escaping () -> Void = {}, onClick: @escaping (Int) -> Void = { _ in }
    ) -> some View {
        modifier(Reorderable(
            id: id, session: session, cornerRadius: cornerRadius, liftedFill: liftedFill, plan: plan, onPress: onPress, onClick: onClick
        ))
    }
}

private struct Reorderable: ViewModifier {
    let id: UUID
    let session: ReorderSession
    let cornerRadius: CGFloat
    let liftedFill: Color
    let plan: () -> ReorderPlan?
    let onPress: () -> Void
    let onClick: (Int) -> Void

    func body(content: Content) -> some View {
        let block = session.lifted
        let isLifted = block.contains(id)
        let offset = isLifted ? session.translation : session.shifts[id] ?? 0
        content
            .background {
                if isLifted {
                    liftedShape(isFirst: block.first == id, isLast: block.last == id)
                        .fill(liftedFill)
                        .shadow(color: .black.opacity(block.count == 1 ? 0.3 : 0), radius: 8)
                }
            }
            .overlay {
                if session.target == id || (isLifted && session.target != nil) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .opacity(isLifted && session.isSinking ? 0 : 1)
            .offset(x: session.axis == .horizontal ? offset : 0, y: session.axis == .vertical ? offset : 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(session.space)) } action: { session.frames[id] = $0 }
            .zIndex(isLifted ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { session.update(id, translation: $0.translation, onPress: onPress, plan: plan) }
                    .onEnded { _ in
                        if session.end() { onClick(NSApp.currentEvent?.clickCount ?? 1) }
                    }
            )
    }

    // A lifted group is one card: only its outer corners are rounded.
    private func liftedShape(isFirst: Bool, isLast: Bool) -> UnevenRoundedRectangle {
        let top = isFirst ? cornerRadius : 0
        let bottom = isLast ? cornerRadius : 0
        return session.axis == .vertical
            ? UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
            : UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius, bottomLeading: cornerRadius, bottomTrailing: cornerRadius, topTrailing: cornerRadius), style: .continuous)
    }
}
