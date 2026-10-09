import AppKit
import HardydoNotesCore
import SwiftUI

final class ProbeWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor
func render(_ window: NSWindow, _ file: String) {
    let view = window.contentView!.superview!
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

@MainActor
func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

nonisolated(unsafe) var eventNumber = 100

@MainActor
func send(_ type: NSEvent.EventType, _ window: NSWindow, _ point: CGPoint, clicks: Int = 1) {
    let location = NSPoint(x: point.x, y: window.contentView!.bounds.height - point.y)
    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: { eventNumber += 1; return eventNumber }(), clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)!
    NSApp.sendEvent(event)
    wait(0.016)
}

@MainActor
func drag(_ window: NSWindow, from start: CGPoint, by delta: CGSize, snapshot: String? = nil) {
    send(.leftMouseDown, window, start)
    let steps = 30
    for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        send(.leftMouseDragged, window, CGPoint(x: start.x + delta.width * t, y: start.y + delta.height * t))
    }
    wait(0.3)
    if let snapshot { render(window, snapshot) }
    send(.leftMouseUp, window, CGPoint(x: start.x + delta.width, y: start.y + delta.height))
    wait(0.4)
}

struct StandardError: TextOutputStream { mutating func write(_ string: String) { FileHandle.standardError.write(string.data(using: .utf8)!) } }
nonisolated(unsafe) var standardError = StandardError()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-drag-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let notesURL = dir.appendingPathComponent("notes.json")
    let groupsURL = dir.appendingPathComponent("groups.json")
    @MainActor func model() -> AppModel { AppModel(store: NoteStore(notesFile: NotesFile(url: notesURL)), groupsFile: JSONFile(url: groupsURL), preferences: Preferences(defaults: defaults)) }
    func groupsBytes() -> Data? { try? Data(contentsOf: groupsURL) }
    func tabsValue() -> String { String(describing: defaults.object(forKey: "openTabs") ?? "nil") + " " + String(describing: defaults.object(forKey: "activeTab") ?? "nil") }
    func report(_ name: String, _ ok: Bool) { print(ok ? "PASS" : "FAIL", name, to: &standardError) }

    let first = model()
    let ids = (0..<4).map { i -> Note.ID in let id = first.store.createNote(); first.store.updateBody(id, "# Note \(i)"); return id }
    first.groups.addToNewGroup(ids[0]); first.groups.add(ids[1], to: first.groups.list.group(of: ids[0])!.id)
    first.tabs.open(ids[2], keep: true); first.tabs.open(ids[3], keep: true)
    report("first quit saves cleanly", first.flushAll() == nil)
    first.store.updateBody(ids[3], "# Note 3 edited")
    _ = first.flushAll()
    let groups = groupsBytes(), tabs = tabsValue()
    report("groups were saved", groups != nil)
    let relaunched = model()
    report("groups come back after a relaunch", relaunched.groups.list == first.groups.list && relaunched.storageProblem == nil)
    try? Data("[".utf8).write(to: groupsURL)
    report("a damaged groups.json raises the storage alert", model().storageProblem != nil)
    try? groups?.write(to: groupsURL)

    try? Data("{\"notes\":[".utf8).write(to: notesURL)
    let restored = model()
    report("damaged notes come back from the previous save", restored.store.notes.count == 4)
    report("a restored load is not clean", !restored.store.loadedCleanly && restored.storageProblem != nil)
    restored.groups.addToNewGroup(ids[2]); restored.tabs.open(ids[1], keep: true)
    _ = restored.flushAll()
    report("groups.json is untouched after a restored load", groupsBytes() == groups)
    report("tabs are untouched after a restored load", tabsValue() == tabs)

    for name in try! FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasPrefix("notes") {
        try? Data("garbage".utf8).write(to: dir.appendingPathComponent(name))
    }
    let empty = model()
    report("both files damaged starts empty", empty.store.notes.isEmpty && empty.storageProblem != nil)
    let fresh = empty.store.createNote(); empty.groups.addToNewGroup(fresh); empty.tabs.open(fresh, keep: true)
    _ = empty.flushAll()
    report("groups.json is untouched after an empty load", groupsBytes() == groups)
    report("tabs are untouched after an empty load", tabsValue() == tabs)
    let backups = try! FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("unreadable") }
    report("damaged files were copied aside", backups.count >= 2)

    defaults.removePersistentDomain(forName: dir.appendingPathComponent("defaults").path)
    try? FileManager.default.removeItem(at: dir)
    exit(0)
}
