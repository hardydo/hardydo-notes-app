import HardydoNotesCore
import SwiftUI

/// Lists the empty notes with a checkbox each, all ticked at first, and deletes only the ticked ones.
struct EmptyNotesConfirmation: View {
    let notes: [Note]
    let onCancel: () -> Void
    let onDelete: (Set<Note.ID>) -> Void
    @StateObject private var chosen: ViewState<Set<Note.ID>>

    private static let rowHeight: CGFloat = 24

    init(notes: [Note], onCancel: @escaping () -> Void, onDelete: @escaping (Set<Note.ID>) -> Void) {
        self.notes = notes
        self.onCancel = onCancel
        self.onDelete = onDelete
        _chosen = StateObject(wrappedValue: ViewState(Set(notes.map(\.id))))
    }

    var body: some View {
        DeleteConfirmation(heading: "Delete empty notes?", message: message, canDelete: !chosen.value.isEmpty, onCancel: onCancel) {
            onDelete(chosen.value)
        } details: {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(notes) { note in
                        Toggle(isOn: binding(for: note.id)) {
                            HStack {
                                Text(note.title).lineLimit(1)
                                Spacer()
                                Text(NoteRow.dateLabel(note.modifiedAt)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12.5))
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 8)
                        .frame(height: Self.rowHeight)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: min(CGFloat(notes.count), 8) * Self.rowHeight + 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        }
    }

    private var message: String {
        let count = chosen.value.count
        let notes = count == 1 ? "1 ticked note" : "\(count) ticked notes"
        return "These notes have no text at all. The \(notes) will be removed from this Mac; locked notes and notes with any text are kept. This can’t be undone."
    }

    private func binding(for id: Note.ID) -> Binding<Bool> {
        Binding {
            chosen.value.contains(id)
        } set: { isOn in
            if isOn { chosen.value.insert(id) } else { chosen.value.remove(id) }
        }
    }
}
