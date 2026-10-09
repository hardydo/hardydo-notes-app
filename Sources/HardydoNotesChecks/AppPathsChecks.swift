import Foundation
import HardydoNotesCore

func runAppPathsChecks() {
    checkEqual(AppPaths.folderName, "com.hardydo.drivenotes", "the data folder keeps the name earlier builds used")
    checkEqual(AppPaths.notesFile.lastPathComponent, "notes.json", "notes are saved in notes.json")
    checkEqual(AppPaths.groupsFile.lastPathComponent, "groups.json", "groups are saved in groups.json")
    checkEqual(AppPaths.notesFile.deletingLastPathComponent(), AppPaths.support, "notes and groups share the data folder")

    let previous = ProcessInfo.processInfo.environment[AppPaths.sandboxVariable]
    let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-paths-\(UUID().uuidString)", isDirectory: true)
    setenv(AppPaths.sandboxVariable, sandbox.path, 1)
    defer {
        if let previous { setenv(AppPaths.sandboxVariable, previous, 1) } else { unsetenv(AppPaths.sandboxVariable) }
    }
    checkEqual(AppPaths.support.standardizedFileURL.path, sandbox.appendingPathComponent(AppPaths.folderName).standardizedFileURL.path,
               "the sandbox variable moves the data folder into it")
    check(!AppPaths.notesFile.path.contains("/Library/Application Support/"), "a sandboxed run never points at the real notes")
}
