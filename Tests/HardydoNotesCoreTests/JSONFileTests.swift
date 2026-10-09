import Foundation
import HardydoNotesCore
import Testing

private func temporaryJSONFile() -> JSONFile<[String]> {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-notes-json-\(UUID().uuidString)")
    return JSONFile<[String]>(url: folder.appendingPathComponent("groups.json"))
}

private func discard(_ file: JSONFile<[String]>) {
    file.flush()
    try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
}

@Suite struct JSONFileTests {
    @Test func missingFileLoadsAsNothingWithoutAProblem() {
        let file = temporaryJSONFile()
        defer { discard(file) }
        #expect(file.load().value == nil && file.load().problem == nil, "a missing file loads as nothing, without a problem")
    }

    @Test func savedValueLoads() {
        let file = temporaryJSONFile()
        defer { discard(file) }
        file.save(["a"])
        file.save(["a", "b"])
        file.flush()
        #expect(file.load().value == ["a", "b"], "the saved value loads")
    }

    @Test func damagedFileFallsBackToThePreviousVersion() {
        let file = temporaryJSONFile()
        defer { discard(file) }
        file.save(["a"])
        file.save(["a", "b"])
        file.flush()
        try? Data("[".utf8).write(to: file.url)
        let damaged = file.load()
        #expect(damaged.value == ["a"], "a damaged file falls back to the previous version")
        #expect(damaged.problem?.contains("restored") == true, "the fallback is reported")
    }

    @Test @MainActor func failedSaveIsReported() async {
        let file = temporaryJSONFile()
        defer { discard(file) }
        file.save(["a"])
        file.flush()
        let blocked = JSONFile<[String]>(url: file.url.appendingPathComponent("inside-a-file.json"))
        var reported: (any Error)?
        blocked.save(["x"]) { reported = $0 }
        #expect(blocked.flush() != nil, "a failed save is returned by flush")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(reported != nil, "a failed save is reported right away")
    }
}
