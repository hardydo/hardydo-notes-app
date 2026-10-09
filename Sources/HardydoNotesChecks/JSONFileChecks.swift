import Foundation
import HardydoNotesCore

@MainActor
func runJSONFileChecks() async {
    let manager = FileManager.default
    let folder = manager.temporaryDirectory.appendingPathComponent("hardydo-notes-json-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: folder) }
    let file = JSONFile<[String]>(url: folder.appendingPathComponent("groups.json"))

    check(file.load().value == nil && file.load().problem == nil, "a missing file loads as nothing, without a problem")
    file.save(["a"])
    file.save(["a", "b"])
    file.flush()
    checkEqual(file.load().value, ["a", "b"], "the saved value loads")

    try? Data("[".utf8).write(to: file.url)
    let damaged = file.load()
    checkEqual(damaged.value, ["a"], "a damaged file falls back to the previous version")
    check(damaged.problem?.contains("restored") == true, "the fallback is reported")

    let blocked = JSONFile<[String]>(url: file.url.appendingPathComponent("inside-a-file.json"))
    var reported: (any Error)?
    blocked.save(["x"]) { reported = $0 }
    check(blocked.flush() != nil, "a failed save is returned by flush")
    try? await Task.sleep(for: .milliseconds(50))
    check(reported != nil, "a failed save is reported right away")
}
