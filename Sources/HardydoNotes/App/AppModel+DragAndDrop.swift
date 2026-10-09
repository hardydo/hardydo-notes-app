import AppKit
import HardydoNotesCore
import UniformTypeIdentifiers

extension AppModel {
    func open(_ urls: [URL], at position: Int = 0) {
        var failures: [String] = []
        for (offset, url) in urls.enumerated() where url.isFileURL {
            do {
                tabs.open(try store.openFile(url, at: position + offset), keep: true)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if !failures.isEmpty {
            dialogs.showAlert("Couldn’t Open File", failures.joined(separator: "\n"))
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .sourceCode, .json, .xml, .html, .yaml]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    /// Escape puts a dragged row back.
    func cancelDrag(on event: NSEvent) -> Bool {
        let sessions = [sidebar.reorder, sidebar.fileReorder, tabs.reorder].filter(\.isDragging)
        guard event.keyCode == 53, !sessions.isEmpty else { return false }
        sessions.forEach { $0.cancel() }
        return true
    }

    /// A file dropped on a note's row opens just above it; anywhere else, at the end.
    func fileDropIndex(at position: CGFloat) -> Int {
        let shown = Set(groups.list.rows(for: store.appNotes).map(\.id) + store.localFileNotes.map(\.id))
        var leads: [UUID: CGFloat] = [:]
        var lengths: [UUID: CGFloat] = [:]
        for session in [sidebar.reorder, sidebar.fileReorder] {
            for (id, frame) in session.frames where shown.contains(id) {
                leads[id] = frame.minY
                lengths[id] = frame.height
            }
        }
        guard let id = ReorderGeometry.row(at: position, leads: leads, lengths: lengths) else { return store.notes.count }
        return store.index(of: id) ?? store.notes.count
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
