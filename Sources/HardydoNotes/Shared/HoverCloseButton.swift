import SwiftUI

/// The ✕ that appears on hover, shared by sidebar rows and tabs; it is only built while it shows.
struct HoverCloseButton: View {
    let size: CGFloat
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size / 2, weight: .bold))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.icon)
        .help(help)
    }
}
