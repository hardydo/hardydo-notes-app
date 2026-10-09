import Foundation
import HardydoNotesCore

/// Each in its own folder, since a save also leaves the previous version beside the file.
func temporaryNotesFile() -> NotesFile {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return NotesFile(url: folder.appendingPathComponent("notes.json"))
}

extension NotesFile {
    /// Queued writes land later, so the folder is removed once every one of them is done.
    func discard() {
        flush()
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
