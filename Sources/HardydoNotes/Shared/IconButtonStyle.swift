import AppKit
import SwiftUI

/// A bare icon button: dimmed at rest, full contrast under the pointer, with the link cursor. A tint, when set, wins over both.
struct IconButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        IconButtonLabel(configuration: configuration, tint: tint)
    }
}

private struct IconButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = ViewState(false)

    var body: some View {
        configuration.label
            .foregroundStyle(tint ?? (hover.value && isEnabled ? Color.primary : Color.secondary))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .contentShape(Rectangle())
            .onHover { hover.value = $0 }
            .pointerStyle(isEnabled ? .link : .default)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// A window-toolbar button drawn by SwiftUI rather than AppKit, whose toolbar items ignore the font, so its symbol matches the sidebar's.
struct ToolbarIconStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .frame(minWidth: 30, minHeight: 28)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .toolbarHover(tint: tint)
    }
}

extension ButtonStyle where Self == ToolbarIconStyle {
    static var toolbarIcon: ToolbarIconStyle { ToolbarIconStyle() }

    static func toolbarToggle(isOn: Bool) -> ToolbarIconStyle { ToolbarIconStyle(tint: isOn ? .accentColor : nil) }
}

extension View {
    /// Brightens a window-toolbar item under the pointer and shows the link cursor over it; a tint, when set, wins.
    func toolbarHover(tint: Color? = nil) -> some View {
        modifier(ToolbarHover(tint: tint))
    }
}

/*
 A pointer style on a toolbar item claims the whole toolbar, so the cursor here follows the item's own hover
 instead, set again on every move because the title bar keeps resetting it to the arrow.
 */
private struct ToolbarHover: ViewModifier {
    let tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var hover = ViewState(false)

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint ?? (hover.value && isEnabled ? Color.primary : Color.secondary))
            .opacity(isEnabled ? 1 : 0.35)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    hover.value = true
                    (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
                case .ended:
                    hover.value = false
                    NSCursor.arrow.set()
                }
            }
    }
}
