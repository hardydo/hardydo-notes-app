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

// Drives find, replace, the search of every note and language detection through the real window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-find-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: dir.appendingPathComponent("notes.json"))), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    let store = model.store
    let a = store.createNote(); store.updateBody(a, "# Alpha\napple pie\nbanana apple\ncherry")
    let b = store.createNote(); store.updateBody(b, "{\n  \"fruit\": \"apple\"\n}\n")
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
    guard let tv = textView() else { print("no editor"); exit(1) }
    window.makeFirstResponder(tv)

    expect(model.workspace.language == .markdown, "a markdown note opens as markdown")
    model.tabs.open(b, keep: true)
    expect(model.workspace.language == .json, "a JSON note is detected the moment it opens")
    model.tabs.activate(a); wait(0.4)

    tv.setSelectedRange(NSRange(location: 0, length: 0))
    model.find.open()
    model.find.setQuery("apple")
    model.find.next()
    wait(0.3)
    let body = store.note(a)!.body as NSString
    let apples = [body.range(of: "apple"), body.range(of: "apple", range: NSRange(location: 15, length: body.length - 15))]
    expect(model.find.ranges == apples, "find lists both matches")
    expect(model.find.current == apples[1], "Return straight after typing moves past the first match of the new query")
    model.find.next(); wait(0.2)
    expect(model.find.current == apples[0], "the next match wraps around")
    model.find.next(forward: false); wait(0.2)
    expect(model.find.current == apples[1], "the previous match wraps around")
    model.find.setQuery("("); model.find.setOptions(SearchOptions(regex: true)); wait(0.3)
    expect(model.find.error != nil && model.find.ranges.isEmpty, "a broken regular expression shows an error")
    model.find.setOptions(SearchOptions())
    model.find.setQuery("apple")
    model.find.replaceText = "pear"
    model.find.replaceAll(); wait(0.4)
    expect(store.note(a)?.body == "# Alpha\npear pie\nbanana pear\ncherry", "replace all replaces every match")
    tv.undoManager?.undo(); wait(0.6)
    expect(tv.string == "# Alpha\napple pie\nbanana apple\ncherry", "replace all undoes in one step")
    model.find.close(); wait(0.2)

    model.openGlobalSearch()
    model.globalSearch.query = "cherry"
    wait(0.6)
    expect(model.globalSearch.results.map(\.id) == [a], "search of every note finds the note")
    if let line = model.globalSearch.results.first?.lines.first {
        model.tabs.open(b)
        wait(0.3)
        model.openResult(a, line)
        wait(0.6)
        expect(model.tabs.selection == a && model.find.current == line.range && textView()?.selectedRange() == line.range, "opening a result selects the match in its note")
    }
    model.globalSearch.query = "zzz"
    wait(0.6)
    expect(model.globalSearch.results.isEmpty && model.globalSearch.matchCount == 0, "a query with no matches clears the results")
    model.closeGlobalSearch()
    window.makeFirstResponder(tv)
    wait(0.2)
    // A string read back from the text storage is not used: AppKit ignores putting it into the same storage again.
    let original = "# Alpha\napple pie\nbanana apple\ncherry"
    expect(tv.string == original, "the note is back to its text before the language checks")
    tv.insertText("{\"now\": \"json\"}", replacementRange: NSRange(location: 0, length: tv.string.utf16.count))
    model.workspace.controller.commit()
    wait(0.05)
    expect(model.workspace.language == .markdown, "the editor keeps the last answer while typing")
    wait(1.0)
    expect(model.workspace.language == .json, "the language is detected again after a pause")
    tv.insertText(original, replacementRange: NSRange(location: 0, length: tv.string.utf16.count))
    model.workspace.controller.commit()
    wait(1.0)
    expect(model.workspace.language == .markdown, "and back to markdown")
    try? FileManager.default.removeItem(at: dir)
    print(failures == 0 ? "all passed" : "\(failures) failed")
    exit(failures == 0 ? 0 : 1)
}
