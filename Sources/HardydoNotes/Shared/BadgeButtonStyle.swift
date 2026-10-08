import AppKit
import SwiftUI

/// The pill used by shadcn's badge: a tinted fill with text in the same hue.
struct BadgeButtonStyle: ButtonStyle {
    let foreground: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
            .pointerStyle(.link)
    }
}

extension Color {
    // shadcn's destructive badge in dark mode: red-400 text on red-500 at 20%.
    static let destructiveText = Color(nsColor: NSColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1))
    static let destructiveFill = Color(nsColor: NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 0.2))
}
