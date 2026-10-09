import AppKit
import WebKit

/// The window-wide input the views cannot see on their own: zoom gestures, shortcuts, the middle button and app activation.
@MainActor
final class InputMonitors {
    private var monitors: [Any] = []
    private var observer: NSObjectProtocol?

    /*
     Each handler returns true when it used the event, which then goes no further. `zoom` gets the factor of a
     pinch or ⌘-scroll over the editor or the preview.
     */
    init(zoom: @escaping @MainActor (CGFloat) -> Void, keyDown: @escaping @MainActor (NSEvent) -> Bool, middleClick: @escaping @MainActor () -> Bool, activated: @escaping @MainActor () -> Void) {
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
                guard let factor = MainActor.assumeIsolated({ Self.zoomFactor(event) }) else { return event }
                MainActor.assumeIsolated { zoom(factor) }
                return nil
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { keyDown(event) } ? nil : event
            },
            NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
                event.buttonNumber == 2 && MainActor.assumeIsolated { middleClick() } ? nil : event
            },
        ].compactMap { $0 }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { activated() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    isolated deinit {
        stop()
    }

    private static func zoomFactor(_ event: NSEvent) -> CGFloat? {
        guard event.type == .magnify || event.modifierFlags.contains(.command),
              let hit = event.window?.contentView?.hitTest(event.locationInWindow),
              sequence(first: hit, next: \.superview).contains(where: { $0 is NSTextView || $0 is WKWebView })
        else { return nil }
        return event.type == .magnify
            ? 1 + event.magnification
            : exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05))
    }
}
