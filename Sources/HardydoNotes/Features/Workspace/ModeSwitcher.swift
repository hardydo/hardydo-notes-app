import AppKit
import SwiftUI

/// Editor / Split / Preview as one row of buttons, each with its own hover, in place of a segmented picker.
struct ModeSwitcher: View {
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: 2) {
            ModeSegment(title: "Editor", isSelected: mode == .edit) { mode = .edit }
            ModeSegment(title: "Split", isSelected: mode == .split) { mode = .split }
            ModeSegment(title: "Preview", isSelected: mode == .preview) { mode = .preview }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

private struct ModeSegment: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var hover = ViewState(false)

    var body: some View {
        Button(action: action) {
            // Sized by the semibold title, so selecting a segment never outgrows the width the toolbar last measured.
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .hidden()
                .overlay {
                    Text(title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected || hover.value ? Color.primary : Color.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.14 : hover.value ? 0.07 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A pointer style in the window toolbar claims the whole bar, so the cursor follows this segment's hover instead.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hover.value = true
                NSCursor.pointingHand.set()
            case .ended:
                hover.value = false
                NSCursor.arrow.set()
            }
        }
    }
}
