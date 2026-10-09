import AppKit
import HardydoNotesCore
import QuartzCore

// Re-wrapping on a width change moves the text under a fixed scroll offset, so the first visible line is pinned across the resize.
final class EditorScrollView: NSScrollView {
    // Exact pinning lays out all text above the anchor, which takes far too long per drag step in a multi-megabyte file.
    private static let exactLimit = 100_000
    private static let wheelDuration: CFTimeInterval = 0.125
    private var dragAnchor: (character: Int, offset: CGFloat)?
    private var settle: Task<Void, Never>?
    private var wheel: (from: CGFloat, to: CGFloat, start: CFTimeInterval)?
    private var wheelLink: CADisplayLink?
    /// Scrolls the reader makes, as opposed to the ones that follow the preview.
    var onScroll: () -> Void = {}
    private var isFollowing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func boundsChanged(_ notification: Notification) {
        if !isFollowing { onScroll() }
    }

    /// The 1-based line at the top of the view, plus the fraction of it scrolled past.
    var topLine: Double? {
        guard let textView = documentView as? CodeTextView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, layoutManager.numberOfGlyphs > 0 else { return nil }
        let top = contentView.bounds.minY - textView.textContainerOrigin.y
        guard top > 0 else { return 1 }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: top), in: container)
        let starts = textView.lines.starts
        let index = textView.lines.line(at: layoutManager.characterIndexForGlyph(at: glyph))
        let rect = lineRect(index, starts, in: textView)
        let fraction = rect.height > 0 ? min(max((top - rect.minY) / rect.height, 0), 1) : 0
        return Double(index + 1) + fraction
    }

    /// Brings `line` (as `topLine` gives it) to the top without reporting the move back.
    func follow(_ line: Double) {
        guard let textView = documentView as? CodeTextView, let layoutManager = textView.layoutManager else { return }
        let starts = textView.lines.starts
        let index = min(max(Int(line) - 1, 0), starts.count - 1)
        let length = textView.textStorage?.length ?? 0
        let start = min(starts[index], length)
        if start > Self.exactLimit {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: start, length: min(1, length - start)))
        } else {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(start + 1, length)))
        }
        let rect = lineRect(index, starts, in: textView)
        let fraction = min(max(line - Double(index + 1), 0), 1)
        let y = line <= 1 ? 0 : rect.minY + fraction * rect.height + textView.textContainerOrigin.y
        stopWheel()
        isFollowing = true
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: clampedY(y)))
        reflectScrolledClipView(contentView)
        isFollowing = false
    }

    // From the top of the line's first fragment to the bottom of its last, so a wrapped line counts as a whole.
    private func lineRect(_ index: Int, _ starts: [Int], in textView: NSTextView) -> NSRect {
        guard let layoutManager = textView.layoutManager else { return .zero }
        let length = textView.textStorage?.length ?? 0
        let start = starts[index]
        let end = index + 1 < starts.count ? starts[index + 1] : length
        guard end > start else { return layoutManager.extraLineFragmentRect }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: end - start), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return .zero }
        let first = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let last = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        return NSRect(x: first.minX, y: first.minY, width: first.width, height: last.maxY - first.minY)
    }

    /*
     A mouse wheel moves in whole notches, which AppKit applies as instant jumps. Like VS Code, each notch is
     eased over a few frames instead; a notch arriving mid-way extends the same glide.
     */
    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 else {
            stopWheel()
            return super.scrollWheel(with: event)
        }
        let current = contentView.bounds.minY
        let target = clampedY((wheel?.to ?? current) - event.scrollingDeltaY * verticalLineScroll)
        guard target != current else { return stopWheel() }
        wheel = (current, target, CACurrentMediaTime())
        if wheelLink == nil {
            let link = displayLink(target: self, selector: #selector(stepWheel))
            link.add(to: .main, forMode: .common)
            wheelLink = link
        }
    }

    @objc private func stepWheel(_ link: CADisplayLink) {
        guard let wheel else { return stopWheel() }
        let progress = min(max((link.targetTimestamp - wheel.start) / Self.wheelDuration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: clampedY(wheel.from + (wheel.to - wheel.from) * eased)))
        reflectScrolledClipView(contentView)
        if progress >= 1 { stopWheel() }
    }

    private func stopWheel() {
        wheelLink?.invalidate()
        wheelLink = nil
        wheel = nil
    }

    private func clampedY(_ y: CGFloat) -> CGFloat {
        var bounds = contentView.bounds
        bounds.origin.y = y
        return contentView.constrainBoundsRect(bounds).minY
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width != frame.width, let anchor = dragAnchor ?? topAnchor() else {
            super.setFrameSize(newSize)
            return
        }
        super.setFrameSize(newSize)
        // A run of resize steps (a window or split drag) restores approximately and settles exactly once it stops.
        if anchor.character <= Self.exactLimit, !inLiveResize, settle == nil {
            restore(anchor, exact: true)
        } else {
            dragAnchor = anchor
            restore(anchor, exact: false)
        }
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.settle = nil
            guard let anchor = self.dragAnchor else { return }
            self.dragAnchor = nil
            self.restore(anchor, exact: true)
        }
    }

    private func topAnchor() -> (character: Int, offset: CGFloat)? {
        guard let textView = documentView as? NSTextView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, layoutManager.numberOfGlyphs > 0 else { return nil }
        let top = contentView.bounds.minY - textView.textContainerOrigin.y
        guard top > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: top), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return (layoutManager.characterIndexForGlyph(at: glyph), top - fragment.minY)
    }

    private func restore(_ anchor: (character: Int, offset: CGFloat), exact: Bool) {
        stopWheel()
        guard let textView = documentView as? NSTextView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, anchor.character < (textView.textStorage?.length ?? 0) else { return }
        if container.size.width != textView.bounds.width {
            container.size = NSSize(width: textView.bounds.width - 2 * textView.textContainerInset.width, height: container.size.height)
        }
        // Lines above the anchor are only estimated with non-contiguous layout and would shift it again later.
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: exact ? 0 : anchor.character, length: exact ? anchor.character + 1 : 1))
        let glyph = layoutManager.glyphIndexForCharacter(at: anchor.character)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let y = fragment.minY + anchor.offset + textView.textContainerOrigin.y
        textView.sizeToFit()
        contentView.scroll(to: NSPoint(x: contentView.bounds.minX, y: max(0, min(y, textView.frame.height - contentView.bounds.height))))
        reflectScrolledClipView(contentView)
    }
}
