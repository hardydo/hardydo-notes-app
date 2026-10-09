import HardydoNotesCore
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
    /// Whether the gap at an index, or its upper half when the flag is set, is a place the block may land.
    let isSlot: (Int, Bool) -> Bool
    /// Rows drawn as headers, which are a different height from the others.
    var headers: Set<UUID> = []
    var startsUpper = false
    var into: Set<UUID> = []
    var lane: (ReorderDrop) -> UUID? = { _ in nil }
    let commit: (ReorderDrop) -> Void
}

/// What one row draws while a drag is on, kept per row so a pointer move redraws only the rows that move.
@MainActor
@Observable
final class ReorderCell {
    fileprivate(set) var offset: CGFloat = 0
    fileprivate(set) var lift: Lift?
    fileprivate(set) var isTarget = false

    struct Lift: Equatable {
        let isFirst: Bool
        let isLast: Bool
        let isAlone: Bool
        var isSinking = false
    }
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
    /// Set from the start of a drag until its drop is committed; a drop onto a collapsed group keeps the last gap's offset.
    private(set) var landing: ReorderLanding?
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    /// The scrolling list's visible frame in global coordinates, and the AppKit view that scrolls it, when the list scrolls.
    @ObservationIgnored var viewport: CGRect?
    @ObservationIgnored weak var scrollView: NSScrollView?
    @ObservationIgnored private var autoscroll: Task<Void, Never>?
    @ObservationIgnored private var scrollObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var cells: [UUID: ReorderCell] = [:]
    @ObservationIgnored private var dropTarget: UUID?
    @ObservationIgnored private var press: Press?
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var settling: Drag?

    private static let startDistance: CGFloat = 4
    private static let hysteresis: CGFloat = 16
    /// How far past a two-halved gap's middle the pointer must go before the drop switches halves.
    private static let halfMargin: CGFloat = 4
    private static let settle = Animation.easeOut(duration: 0.2)
    /// Within this distance of the list's edge a dragged row scrolls the list, faster the closer it gets.
    private static let scrollEdge: CGFloat = 24
    private static let maxScrollStep: CGFloat = 12

    private struct Press {
        let id: UUID
        let start: CGPoint
        var moved = false
        var refused = false
    }

    private struct Drag {
        let plan: ReorderPlan
        let geometry: ReorderGeometry
        let scrollStart: CGFloat
        var drop: ReorderDrop
        var anchor: CGFloat = 0
        var pointer: CGFloat = 0
        var location: CGFloat = 0
    }

    init(axis: Axis, space: String) {
        self.axis = axis
        self.space = space
    }

    var isPressed: Bool { press != nil }
    var isDragging: Bool { drag != nil }

    func cell(_ id: UUID) -> ReorderCell {
        if let cell = cells[id] { return cell }
        let cell = ReorderCell()
        cells[id] = cell
        return cell
    }

    func update(_ id: UUID, start: CGPoint = .zero, location: CGPoint = .zero, translation: CGSize, onPress: () -> Void, plan: () -> ReorderPlan?) {
        if press?.id != id || press?.start != start {
            // A gesture SwiftUI dropped without ending it would otherwise leave its rows lifted.
            if drag != nil { cancel() }
            commitSettling()
            press = Press(id: id, start: start)
            onPress()
        }
        let distance = hypot(translation.width, translation.height)
        if distance >= Self.startDistance { press?.moved = true }
        if drag == nil {
            guard distance >= Self.startDistance, press?.refused == false else { return }
            guard let plan = plan(), let started = begin(plan) else {
                press?.refused = true
                return
            }
            drag = started
            setLifted(plan.block)
            landing = Self.landing(started.drop, in: started, keeping: nil)
            watchScrolling()
        }
        drag?.pointer = axis == .vertical ? translation.height : translation.width
        drag?.location = axis == .vertical ? location.y : location.x
        follow()
        steerAutoscroll()
    }

    /// Ends the press; true when it was a click rather than a drag.
    func end() -> Bool {
        defer { press = nil }
        guard let drag else { return press?.moved == false }
        self.drag = nil
        stopScrolling()
        settling = drag
        withAnimation(Self.settle) {
            switch drag.drop {
            case .slot:
                setTranslation(landing?.offset ?? 0)
            case .into(let group):
                setShifts(drag.geometry.shifts(forGapAt: drag.geometry.remaining.count))
                setTranslation((drag.geometry.leads[group] ?? 0) + (shifts[group] ?? 0) - drag.geometry.blockLead)
                setSinking(true)
            }
        } completion: { [weak self] in
            self?.commitSettling()
        }
        return false
    }

    /// Puts the lifted rows back where they started without changing anything; the rest of the press is ignored.
    func cancel() {
        press?.refused = true
        guard drag != nil else { return }
        drag = nil
        stopScrolling()
        withAnimation(Self.settle) {
            setTranslation(0)
            setShifts([:])
            setDropTarget(nil)
            landing = nil
        } completion: { [weak self] in
            guard let self, self.drag == nil, self.settling == nil else { return }
            withAnimation(.easeOut(duration: 0.12)) { self.setLifted([]) }
        }
    }

    // Every row already shows where the new order puts it, so the model catches up without anything moving.
    private func commitSettling() {
        guard let drag = settling else { return }
        settling = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag.plan.commit(drag.drop)
            setTranslation(0)
            setShifts([:])
            setDropTarget(nil)
            landing = nil
            setSinking(false)
        }
        withAnimation(.easeOut(duration: 0.12)) { setLifted([]) }
    }

    /*
     A lazy list has not built the rows far off screen, and the frames it last reported for them go stale, so rows
     are laid end to end from the pressed one, each as long as its own last frame or a built row of its kind.
     */
    private func begin(_ plan: ReorderPlan) -> Drag? {
        guard let pressed = plan.block.first, let start = plan.rows.firstIndex(of: pressed), let anchor = frames[pressed] else { return nil }
        let length = { (frame: CGRect) in self.axis == .vertical ? frame.height : frame.width }
        var typical: [Bool: CGFloat] = [:]
        for id in plan.rows where typical.count < 2 {
            if let frame = frames[id], typical[plan.headers.contains(id)] == nil { typical[plan.headers.contains(id)] = length(frame) }
        }
        var lengths: [UUID: CGFloat] = [:]
        for id in plan.rows {
            guard let value = frames[id].map(length) ?? typical[plan.headers.contains(id)] ?? typical.values.first else { return nil }
            lengths[id] = value
        }
        var leads: [UUID: CGFloat] = [:]
        var position = axis == .vertical ? anchor.minY : anchor.minX
        for id in plan.rows[start...] {
            leads[id] = position
            position += lengths[id] ?? 0
        }
        position = axis == .vertical ? anchor.minY : anchor.minX
        for id in plan.rows[..<start].reversed() {
            position -= lengths[id] ?? 0
            leads[id] = position
        }
        guard let geometry = ReorderGeometry(rows: plan.rows, block: plan.block, leads: leads, lengths: lengths) else { return nil }
        return Drag(plan: plan, geometry: geometry, scrollStart: scrollOffset, drop: .slot(geometry.startIndex, upper: plan.startsUpper))
    }

    // The pointer stays put while the list scrolls under it, so the lifted row moves by however far the list has scrolled.
    private func follow() {
        guard let drag else { return }
        move(drag.pointer + scrollOffset - drag.scrollStart)
    }

    /// How far the list is scrolled from its start, growing as later rows come into view.
    private var scrollOffset: CGFloat {
        guard let scrollView, let document = scrollView.documentView else { return 0 }
        let bounds = scrollView.contentView.bounds
        if axis == .horizontal { return bounds.minX }
        return document.isFlipped ? bounds.minY : document.frame.height - bounds.maxY
    }

    private func watchScrolling() {
        guard let clip = scrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    private func stopScrolling() {
        autoscroll?.cancel()
        autoscroll = nil
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
    }

    private func steerAutoscroll() {
        guard autoscroll == nil, edgeSpeed() != 0 else { return }
        autoscroll = Task { [weak self] in
            while !Task.isCancelled, let speed = self?.edgeSpeed(), speed != 0 {
                self?.scroll(by: speed)
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { self?.autoscroll = nil }
        }
    }

    private func edgeSpeed() -> CGFloat {
        guard let drag, let viewport, scrollView != nil else { return 0 }
        let low = axis == .vertical ? viewport.minY : viewport.minX
        let high = axis == .vertical ? viewport.maxY : viewport.maxX
        let depth = drag.location < low + Self.scrollEdge ? drag.location - low - Self.scrollEdge
            : drag.location > high - Self.scrollEdge ? drag.location - high + Self.scrollEdge : 0
        return Self.maxScrollStep * max(-1, min(1, depth / Self.scrollEdge))
    }

    private func scroll(by distance: CGFloat) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        if axis == .vertical {
            let limit = max(0, document.frame.height - clip.bounds.height)
            let current = document.isFlipped ? origin.y : limit - origin.y
            let next = min(max(current + distance, 0), limit)
            origin.y = document.isFlipped ? next : limit - next
        } else {
            origin.x = min(max(origin.x + distance, 0), max(0, document.frame.width - clip.bounds.width))
        }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /*
     The row stops at the list's ends but the drop follows the pointer past them: the gap after a group that ends
     the list has a lower half only a pointer beyond the clamped row can reach.
     */
    private func move(_ value: CGFloat) {
        guard var drag else { return }
        setTranslation(drag.geometry.clamped(value))
        let center = drag.geometry.blockLead + value + drag.geometry.blockLength / 2
        guard let next = drop(at: center, moved: value, in: drag), next != drag.drop else { return }
        var nextShifts = shifts
        if let index = next.index, index != drag.drop.index {
            nextShifts = drag.geometry.shifts(forGapAt: index)
            guard !movesAway(nextShifts, before: center, in: drag) else { return }
            drag.anchor = value
        }
        drag.drop = next
        self.drag = drag
        withAnimation(Self.settle) {
            setShifts(nextShifts)
            if case .into(let group) = next { setDropTarget(group) } else { setDropTarget(nil) }
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
            guard let nearest = drag.geometry.nearestSlot(to: center, where: { plan.isSlot($0, false) || plan.isSlot($0, true) })
            else { return nil }
            index = nearest
        }
        switch (plan.isSlot(index, false), plan.isSlot(index, true)) {
        case (true, false): return .slot(index, upper: false)
        case (false, true): return .slot(index, upper: true)
        case (false, false): return drag.drop
        case (true, true):
            let offset = center - drag.geometry.slotCenter(index)
            if case .slot(index, let upper) = drag.drop, abs(offset) <= Self.halfMargin { return .slot(index, upper: upper) }
            return .slot(index, upper: offset < 0)
        }
    }

    // A collapsed group's header must not slide out from under a note heading for it before the note can be dropped on it.
    private func movesAway(_ next: [UUID: CGFloat], before center: CGFloat, in drag: Drag) -> Bool {
        drag.plan.into.contains { id in
            guard let lead = drag.geometry.leads[id], let length = drag.geometry.lengths[id] else { return false }
            let now = shifts[id] ?? 0
            let then = next[id] ?? 0
            let top = lead + now
            if then < now { return center <= top + length * 0.75 }
            if then > now { return center >= top + length * 0.25 }
            return false
        }
    }

    // The middle half of a collapsed group's header takes the note in, as dropping on a closed folder does.
    private func isOver(_ id: UUID, at center: CGFloat, in drag: Drag) -> Bool {
        guard let lead = drag.geometry.leads[id], let length = drag.geometry.lengths[id] else { return false }
        let top = lead + (shifts[id] ?? 0)
        return center > top + length * 0.25 && center < top + length * 0.75
    }

    private static func landing(_ drop: ReorderDrop, in drag: Drag, keeping current: ReorderLanding?) -> ReorderLanding {
        let offset = drop.index.map(drag.geometry.landingOffset) ?? current?.offset ?? 0
        return ReorderLanding(offset: offset, lane: drag.plan.lane(drop))
    }

    private func setLifted(_ block: [UUID]) {
        for id in lifted where !block.contains(id) { cells[id]?.lift = nil }
        for (index, id) in block.enumerated() {
            cell(id).lift = ReorderCell.Lift(isFirst: index == 0, isLast: index == block.count - 1, isAlone: block.count == 1)
        }
        lifted = block
    }

    private func setTranslation(_ value: CGFloat) {
        translation = value
        for id in lifted where cells[id]?.offset != value { cells[id]?.offset = value }
    }

    private func setShifts(_ next: [UUID: CGFloat]) {
        for id in Set(shifts.keys).union(next.keys) where cells[id]?.lift == nil {
            let offset = next[id] ?? 0
            if cells[id]?.offset ?? 0 != offset { cell(id).offset = offset }
        }
        shifts = next
    }

    private func setDropTarget(_ id: UUID?) {
        guard id != dropTarget else { return }
        if let old = dropTarget { cells[old]?.isTarget = false }
        dropTarget = id
        if let id { cell(id).isTarget = true }
        for liftedID in lifted { cells[liftedID]?.isTarget = id != nil }
    }

    private func setSinking(_ isSinking: Bool) {
        for id in lifted { cells[id]?.lift?.isSinking = isSinking }
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
        let cell = session.cell(id)
        let lift = cell.lift
        content
            .background {
                if let lift {
                    liftedShape(isFirst: lift.isFirst, isLast: lift.isLast)
                        .fill(liftedFill)
                        .shadow(color: .black.opacity(lift.isAlone ? 0.3 : 0), radius: 8)
                }
            }
            .overlay {
                if cell.isTarget {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .opacity(lift?.isSinking == true ? 0 : 1)
            .offset(x: session.axis == .horizontal ? cell.offset : 0, y: session.axis == .vertical ? cell.offset : 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(session.space)) } action: { session.frames[id] = $0 }
            .zIndex(lift != nil ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { session.update(id, start: $0.startLocation, location: $0.location, translation: $0.translation, onPress: onPress, plan: plan) }
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

/// Hands the scroll view a reorderable list sits in to its sessions, so a drag can follow and drive its scrolling.
struct ReorderScrollAnchor: NSViewRepresentable {
    let sessions: [ReorderSession]

    func makeNSView(context: Context) -> NSView { Installer(sessions: sessions) }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Installer: NSView {
        let sessions: [ReorderSession]

        init(sessions: [ReorderSession]) {
            self.sessions = sessions
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let scrollView = enclosingScrollView else { return }
            for session in sessions { session.scrollView = scrollView }
        }
    }
}
