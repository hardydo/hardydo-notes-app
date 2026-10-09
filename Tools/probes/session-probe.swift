import AppKit
import HardydoNotesCore
import SwiftUI

final class ProbeWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor
func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

nonisolated(unsafe) var failures = 0
func expect(_ condition: Bool, _ name: String) {
    print(condition ? "ok  " : "FAIL", name)
    if !condition { failures += 1 }
}

// Drives per-tab editors through switching, undo, outside changes and closing tabs.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-session-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: dir.appendingPathComponent("notes.json"))), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    let store = model.store
    let a = store.createNote(); store.updateBody(a, "# Alpha\n{\n  \"x\": 1\n}\n")
    let b = store.createNote(); store.updateBody(b, "# Beta\ntext")
    model.tabs.open(a, keep: true)
    let window = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.contentViewController = NSHostingController(rootView: ContentView(model: model))
    window.setFrame(NSRect(x: 40, y: 40, width: 1000, height: 600), display: true)
    window.alphaValue = 0
    window.orderFrontRegardless()
    model.start()
    wait(1.2)
    func textView() -> CodeTextView? {
        var stack: [NSView] = [window.contentView!]
        while let v = stack.popLast() { if let tv = v as? CodeTextView { return tv }; stack += v.subviews }
        return nil
    }
    guard let first = textView() else { print("no editor"); exit(1) }
    window.makeFirstResponder(first)
    first.setSelectedRange(NSRange(location: 7, length: 0))
    first.insertText(" one", replacementRange: first.selectedRange())
    model.tabs.open(b, keep: true); wait(0.6)
    expect(store.note(a)?.body.hasPrefix("# Alpha one") == true, "typing is saved when switching away before the pause")
    let second = textView()
    expect(second !== first && second?.string == "# Beta\ntext", "the other tab shows its own editor")
    expect(window.firstResponder === second, "the keyboard follows to the next tab's editor")
    model.tabs.activate(a); wait(0.6)
    expect(textView() === first, "switching back reuses the same editor")
    first.undoManager?.undo(); wait(0.4)
    expect(first.string.hasPrefix("# Alpha\n"), "undo still works after switching tabs")
    model.tabs.open(b); wait(0.4)
    store.updateBody(a, "# Alpha changed elsewhere\n")
    model.tabs.activate(a); wait(0.6)
    expect(textView()?.string == "# Alpha changed elsewhere\n", "a change made while the tab was hidden shows on return")
    model.tabs.close(b); wait(0.4)
    expect(model.tabs.list.ids == [a], "closing a tab removes it")
    model.tabs.open(b, keep: true); wait(0.6)
    expect(textView() !== second, "a reopened tab gets a fresh editor")

    let json = store.createNote(); store.updateBody(json, "{\n  \"key\": [1, 2, 3]\n}\n")
    model.tabs.setPinned(b, true)
    model.tabs.open(json, keep: true); wait(0.4)
    expect(model.workspace.language == .json, "a JSON tab is coloured as JSON")
    _ = model.flushAll()
    let relaunched = AppModel(store: NoteStore(notesFile: NotesFile(url: dir.appendingPathComponent("notes.json"))), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    expect(relaunched.tabs.list.ids == model.tabs.list.ids && relaunched.tabs.selection == json && relaunched.tabs.isPinned(b), "tabs, the active tab and pinned tabs come back after a relaunch")
    expect(relaunched.workspace.language == .json, "the restored tab's language is known before the first draw")
    let alphaRow = relaunched.sidebar.rowState(a)
    expect(relaunched.sidebar.rowState(json).isSelected && !alphaRow.isSelected, "the restored tab's sidebar row is highlighted")
    relaunched.tabs.activate(a)
    expect(relaunched.workspace.language == .markdown && alphaRow.isSelected && !relaunched.sidebar.rowState(json).isSelected, "switching tabs moves the highlight and the language")
    relaunched.find.current = NSRange(location: 0, length: 1); relaunched.workspace.controller.pendingReveal = NSRange(location: 0, length: 1)
    relaunched.tabs.activate(json)
    expect(relaunched.find.current == nil && relaunched.workspace.controller.pendingReveal == nil, "switching tabs drops the old tab's find match and pending reveal")
    defaults.removePersistentDomain(forName: dir.appendingPathComponent("defaults").path)
    try? FileManager.default.removeItem(at: dir)
    print(failures == 0 ? "all passed" : "\(failures) failed")
    exit(failures == 0 ? 0 : 1)
}
