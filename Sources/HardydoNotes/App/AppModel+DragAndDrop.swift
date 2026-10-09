import AppKit
import HardydoNotesCore
import UniformTypeIdentifiers

extension AppModel {
    /// Escape puts a dragged row back.
    func cancelDrag(on event: NSEvent) -> Bool {
        let sessions = [sidebarReorder, fileReorder, tabReorder].filter(\.isDragging)
        guard event.keyCode == 53, !sessions.isEmpty else { return false }
        sessions.forEach { $0.cancel() }
        return true
    }

    /// A file dropped on a note's row opens just above it; anywhere else, at the end.
    func fileDropIndex(at position: CGFloat) -> Int {
        let shown = Set(groups.rows(for: store.appNotes).map(\.id) + store.localFileNotes.map(\.id))
        var leads: [UUID: CGFloat] = [:]
        var lengths: [UUID: CGFloat] = [:]
        for session in [sidebarReorder, fileReorder] {
            for (id, frame) in session.frames where shown.contains(id) {
                leads[id] = frame.minY
                lengths[id] = frame.height
            }
        }
        guard let id = ReorderGeometry.row(at: position, leads: leads, lengths: lengths) else { return store.notes.count }
        return store.notes.firstIndex { $0.id == id } ?? store.notes.count
    }

    func openDropped(_ providers: [NSItemProvider], at position: Int) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { open(urls, at: position) }
        }
    }
}
