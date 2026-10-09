import HardydoNotesCore
import SwiftUI

/// A sidebar row. Hover and selection live in the row, so moving the pointer or the selection redraws only the rows involved.
struct NoteRow: View {
    let note: NoteSummary
    let state: RowState
    let actions: NoteRowActions
    @StateObject private var hover = ViewState(false)

    private var isHovered: Bool { hover.value }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.dateLabel(note.modifiedAt)).monospacedDigit()
                    Text(note.snippet.isEmpty ? "No additional text" : note.snippet).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            ZStack(alignment: .trailing) {
                indicators
                    .opacity(isHovered && !note.isLocked ? 0 : 1)
                if isHovered && !note.isLocked {
                    HoverCloseButton(size: 18, help: note.filePath == nil ? "Delete Note" : "Close File (the file stays on disk)") {
                        actions.remove(note.id)
                    }
                }
            }
            .frame(minWidth: 18, alignment: .trailing)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(state.isSelected ? Color.accentColor.opacity(0.22) : isHovered ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hover.value = inside
            if inside {
                actions.model.noteUnderPointer = note.id
            } else if actions.model.noteUnderPointer == note.id {
                actions.model.noteUnderPointer = nil
            }
        }
        .contextMenu { NoteContextMenu(model: actions.model, note: note) }
    }

    private var indicators: some View {
        HStack(spacing: 5) {
            if note.isPinned {
                Image(systemName: "pin.fill").rotationEffect(.degrees(45)).help("Pinned to the top")
            }
            if note.isLocked {
                Image(systemName: "lock.fill").help("Locked (read-only)")
            }
            if let path = note.filePath {
                Image(systemName: "doc").help(path)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    private static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return calendar.isDate(date, equalTo: Date(), toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

@MainActor
struct NoteRowActions {
    let model: AppModel
    let focusList: () -> Void

    func select(_ id: Note.ID) {
        model.selectNote(id)
        focusList()
    }

    func keep(_ id: Note.ID) { model.keepTab(id) }
    func remove(_ id: Note.ID) { model.requestDelete(id) }
}
