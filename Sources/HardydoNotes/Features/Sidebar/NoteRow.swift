import HardydoNotesCore
import SwiftUI

/// A sidebar row. Hover lives in the row, so moving the pointer redraws only the rows it crosses.
struct NoteRow: View, Equatable {
    let note: Note
    let isSelected: Bool
    let actions: NoteRowActions
    @StateObject private var hover = ViewState(false)

    private var isHovered: Bool { hover.value }

    nonisolated static func == (lhs: NoteRow, rhs: NoteRow) -> Bool {
        MainActor.assumeIsolated { lhs.note == rhs.note && lhs.isSelected == rhs.isSelected }
    }

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
                if !note.isLocked {
                    HoverCloseButton(isVisible: isHovered, size: 18, help: note.localFile == nil ? "Delete Note" : "Close File (the file stays on disk)") {
                        actions.remove(note.id)
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : isHovered ? Color.primary.opacity(0.05) : .clear)
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
        .onDrop(of: [.fileURL], isTargeted: nil) { actions.openFiles($0, at: note.id) }
    }

    private var indicators: some View {
        HStack(spacing: 5) {
            if note.isPinned {
                Image(systemName: "pin.fill").rotationEffect(.degrees(45)).help("Pinned to the top")
            }
            if note.isLocked {
                Image(systemName: "lock.fill").help("Locked (read-only)")
            }
            if let path = note.localFile?.path {
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

/// The ✕ that appears on hover, shared by sidebar rows and tabs.
struct HoverCloseButton: View {
    let isVisible: Bool
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
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .help(help)
    }
}
