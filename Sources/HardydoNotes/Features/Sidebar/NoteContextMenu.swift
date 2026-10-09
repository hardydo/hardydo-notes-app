import AppKit
import HardydoNotesCore
import SwiftUI

struct NoteContextMenu: View {
    let model: AppModel
    let note: NoteSummary

    var body: some View {
        Button("Open in New Tab") { model.selectNote(note.id, keep: true) }
        Button(note.isPinned ? "Unpin Note" : "Pin Note to Top") { model.setPinned(note.id, !note.isPinned) }
        Button(note.isLocked ? "Unlock" : "Lock (Read-Only)") { model.setLocked(note.id, !note.isLocked) }
        Divider()
        if let path = note.filePath {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Button("Close File") { model.closeFile(note.id) }
        } else {
            Menu("Add to Group") {
                Button("New Group") { model.addToNewGroup(note.id) }
                let others = model.groups.groups.filter { $0.id != model.groups.group(of: note.id)?.id }
                if !others.isEmpty { Divider() }
                ForEach(others) { group in
                    Button(group.displayName) { model.add(note.id, toGroup: group.id) }
                }
            }
            if model.groups.group(of: note.id) != nil {
                Button("Remove from Group") { model.removeFromGroup(note.id) }
            }
            Divider()
            Button("Rename…") { model.requestRename(note.id) }
                .disabled(note.isLocked)
            Button("Delete Note…", role: .destructive) { model.requestDelete(note.id) }
                .disabled(note.isLocked)
        }
    }
}
