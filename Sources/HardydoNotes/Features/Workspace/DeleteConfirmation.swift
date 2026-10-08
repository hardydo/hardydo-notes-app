import SwiftUI

// A sheet of its own, since the system alert cannot style its buttons. Return cancels; deleting takes a click or ⌘⌫.
struct DeleteConfirmation: View {
    var heading = "Delete this note?"
    let message: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(BadgeButtonStyle(foreground: .primary, background: Color.primary.opacity(0.09)))
                    .keyboardShortcut(.defaultAction)
                Button("Delete", action: onDelete)
                    .buttonStyle(BadgeButtonStyle(foreground: .destructiveText, background: .destructiveFill))
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 340)
        .onExitCommand(perform: onCancel)
    }
}
