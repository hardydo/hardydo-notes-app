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
    let top = NSRect(x: 0, y: view.bounds.height - 56, width: view.bounds.width, height: 56)
    let rep = view.bitmapImageRepForCachingDisplay(in: top)!
    view.cacheDisplay(in: top, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

@MainActor
func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

// Usage: toolbar-shot <output folder>; renders the toolbar strip for a Markdown, locked, JSON and split-view note.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let out = CommandLine.arguments.dropFirst().first ?? "."
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-shot-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: dir.appendingPathComponent("notes.json"))), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    let store = model.store
    let md = store.createNote(); store.updateBody(md, "# Markdown note\ntext")
    let json = store.createNote(); store.updateBody(json, "{\n  \"a\": 1,\n  \"b\": [1, 2]\n}\n")
    model.tabs.open(md, keep: true)
    let window = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 620), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingController(rootView: ContentView(model: model))
    host.sceneBridgingOptions = [.toolbars, .title]
    window.contentViewController = host
    window.setFrame(NSRect(x: 40, y: 40, width: 1100, height: 620), display: true)
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
    model.start()
    wait(1.5)
    render(window, "\(out)/1-markdown.png"); print("title:", window.title)
    store.setLocked(md, true); wait(0.8)
    render(window, "\(out)/2-locked.png")
    store.setLocked(md, false)
    model.tabs.open(json, keep: true); wait(1.2)
    render(window, "\(out)/3-json.png"); print("title:", window.title)
    model.tabs.open(md); model.workspace.viewMode = .split; wait(1.2)
    render(window, "\(out)/4-split.png")
    model.workspace.viewMode = .preview; wait(1.2)
    render(window, "\(out)/5-preview.png"); print("title:", window.title)
    try? FileManager.default.removeItem(at: dir)
    exit(0)
}
