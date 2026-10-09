import AppKit
import HardydoNotesCore
import SwiftUI

final class ProbeWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor
func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor
func render(_ view: NSView, _ file: String) {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

// Usage: editor-shot <output folder>; shoots a JSON note's editor before typing, right after Return, and once coloured again.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let out = CommandLine.arguments.dropFirst().first ?? "."
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-editor-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: dir.appendingPathComponent("notes.json"))), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    let note = model.store.createNote()
    model.store.updateBody(note, "{\n  \"name\": \"Hardydo\",\n  \"tags\": [\n    \"notes\",\n    \"mac\"\n  ],\n  \"settings\": {\n    \"zoom\": 1.25,\n    \"dark\": true\n  }\n}\n")
    model.tabs.open(note, keep: true)
    let window = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 520), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentViewController = NSHostingController(rootView: ContentView(model: model))
    window.setFrame(NSRect(x: 40, y: 40, width: 900, height: 520), display: true)
    window.alphaValue = 0
    window.orderFrontRegardless()
    model.start()
    wait(1.5)
    var stack: [NSView] = [window.contentView!]
    var found: CodeTextView?
    while let v = stack.popLast() { if let tv = v as? CodeTextView { found = tv; break }; stack += v.subviews }
    guard let tv = found, let scroll = tv.enclosingScrollView else { print("no editor"); exit(1) }
    window.makeFirstResponder(tv)
    render(scroll, "\(out)/1-before.png")
    tv.setSelectedRange(NSRange(location: 1, length: 0))
    tv.insertText("\n", replacementRange: tv.selectedRange())
    tv.displayIfNeeded(); scroll.verticalRulerView?.displayIfNeeded()
    render(scroll, "\(out)/2-after-return.png")
    wait(1.0)
    render(scroll, "\(out)/3-recoloured.png")
    try? FileManager.default.removeItem(at: dir)
    exit(0)
}
