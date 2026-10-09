import AppKit
import SwiftUI

/// A slim scroll bar like VS Code's: a square knob on a clear track, narrower than AppKit's legacy scroller.
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 10 }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnob() {
        let isVertical = bounds.height >= bounds.width
        let knob = rect(for: .knob).insetBy(dx: isVertical ? 2.5 : 2, dy: isVertical ? 2 : 2.5)
        guard knob.width > 0, knob.height > 0 else { return }
        NSColor.labelColor.withAlphaComponent(0.28).setFill()
        knob.fill()
    }
}

struct ThinScrollBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Installer() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Installer: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let scrollView = enclosingScrollView, !(scrollView.verticalScroller is ThinScroller) else { return }
            scrollView.verticalScroller = ThinScroller()
        }
    }
}
