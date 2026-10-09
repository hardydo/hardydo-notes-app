import SwiftUI

// A sheet of its own, since the system alert cannot style its buttons. Return cancels; deleting takes a click or ⌘⌫.
struct DeleteConfirmation<Details: View>: View {
    let heading: String
    let message: String
    let canDelete: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void
    let details: Details

    init(heading: String = "Delete this note?", message: String, canDelete: Bool = true, onCancel: @escaping () -> Void, onDelete: @escaping () -> Void, @ViewBuilder details: () -> Details) {
        self.heading = heading
        self.message = message
        self.canDelete = canDelete
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            details
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(BadgeButtonStyle(foreground: .primary, background: Color.primary.opacity(0.09)))
                    .keyboardShortcut(.defaultAction)
                Button("Delete", action: onDelete)
                    .buttonStyle(BadgeButtonStyle(foreground: .destructiveText, background: .destructiveFill))
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!canDelete)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 340)
        .onExitCommand(perform: onCancel)
    }
}

extension DeleteConfirmation where Details == EmptyView {
    init(heading: String = "Delete this note?", message: String, onCancel: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.init(heading: heading, message: message, onCancel: onCancel, onDelete: onDelete) { EmptyView() }
    }
}
