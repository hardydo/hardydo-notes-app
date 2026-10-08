import AppKit
import QuartzCore

/// VS Code's smooth caret: the text view's own caret is hidden and this bar slides to each new place, then blinks while it rests.
final class SmoothCaret: NSView {
    private static let slide = 0.08
    private var target: NSRect?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        bounds.fill()
    }

    /// Nil hides the caret; a move made while it is showing slides there instead of jumping.
    func move(to rect: NSRect?, animated: Bool) {
        guard let rect else {
            isHidden = true
            target = nil
            return
        }
        if rect == target, !isHidden { return }
        let slides = animated && target != nil && !isHidden
        target = rect
        isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = slides ? Self.slide : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().frame = rect
        }
        restartBlink()
    }

    // Like the system caret, it stays solid while moving and blinks once it rests.
    private func restartBlink() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "blink")
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0]
        blink.keyTimes = [0, 0.5, 0.5, 1]
        blink.duration = 1.06
        blink.repeatCount = .infinity
        layer.add(blink, forKey: "blink")
    }
}
