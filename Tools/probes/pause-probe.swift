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
    // Without this an invisible window's timers are coalesced, and the stall monitor reports idle gaps as stalls.
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "probe")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-drag-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: dir.appendingPathComponent("notes.json"))), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    let kind = CommandLine.arguments.dropFirst().first ?? "md"
    let big = model.store.createNote()
    let body: String
    switch kind {
    case "json": body = "{\n" + (1...20_000).map { "  \"key\($0)\": {\"name\": \"value \($0)\", \"items\": [1, 2, 3]}," }.joined(separator: "\n") + "\n  \"end\": true\n}"
    case "json400": body = "{\n" + (1...8_000).map { "  \"key\($0)\": {\"name\": \"value \($0)\", \"items\": [1, 2, 3]}," }.joined(separator: "\n") + "\n  \"end\": true\n}"
    case "vi": body = "# Ghi chú\n" + (1...20_000).map { "Dòng \($0): tiếng Việt có **dấu** và `code` ở đây nhé" }.joined(separator: "\n")
    default: body = "# Big\n" + (1...25_000).map { "Line \($0): some **markdown** with `code` and [link](https://x.y) text here" }.joined(separator: "\n")
    }
    model.store.updateBody(big, body)
    let window = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingController(rootView: ContentView(model: model))
    window.contentViewController = host
    window.setFrame(NSRect(x: 40, y: 40, width: 1100, height: 700), display: true)
    window.alphaValue = 0
    window.orderFrontRegardless()
    model.start()
    model.tabs.open(big)
    wait(2.5)
    var stack: [NSView] = [window.contentView!]
    var found: CodeTextView?
    while let v = stack.popLast() { if let tv = v as? CodeTextView { found = tv; break }; stack += v.subviews }
    guard let tv = found else { print("no tv"); exit(1) }
    print("kind:", kind, "chars:", tv.string.utf16.count, "language:", model.workspace.language, to: &standardError)
    window.makeFirstResponder(tv)
    if CommandLine.arguments.contains("reads") {
        var s = CFAbsoluteTimeGetCurrent()
        var total = 0
        for _ in 0..<200 { total &+= tv.string.utf16.count }
        print("200 reads of textView.string.utf16.count:", String(format: "%.2f ms", (CFAbsoluteTimeGetCurrent() - s) * 1000), to: &standardError)
        let other = String(tv.string.reversed().reversed())
        s = CFAbsoluteTimeGetCurrent()
        var eq = 0
        for _ in 0..<10 { if tv.string != other { eq += 1 } }
        print("10 full compares textView.string != equal copy:", String(format: "%.2f ms", (CFAbsoluteTimeGetCurrent() - s) * 1000), to: &standardError)
    }

    /*
     Main-thread stall monitor: the longest stretch the main run loop stayed busy between waking and going back to
     sleep, as hang detectors measure it. Timer gaps also count idle time the system delays timers by.
     */
    @MainActor final class Stall { var last = CFAbsoluteTimeGetCurrent(); var worst = 0.0; var woke: CFAbsoluteTime? }
    let stall = Stall()
    let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
        MainActor.assumeIsolated {
            let now = CFAbsoluteTimeGetCurrent()
            if activity == .afterWaiting {
                stall.woke = now
            } else if let woke = stall.woke {
                stall.worst = max(stall.worst, now - woke)
                stall.woke = nil
            }
        }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    @MainActor func measurePause(_ label: String, _ action: () -> Void) {
        wait(1.5)
        stall.worst = 0; stall.woke = nil
        action()
        wait(1.5)
        print(label, "worst main-thread stall over 1.5 s:", String(format: "%.1f ms", stall.worst * 1000), to: &standardError)
    }
    if CommandLine.arguments.count > 2 {
        if CommandLine.arguments[2] == "split" { model.workspace.viewMode = .split; wait(2) }
        if CommandLine.arguments.contains("find") { model.find.open(); model.find.setQuery("code"); wait(2); print("find matches:", model.find.ranges.count, to: &standardError) }
        print("READY", to: &standardError)
        tv.setSelectedRange(NSRange(location: CommandLine.arguments.contains("top") ? 10 : tv.string.utf16.count / 2, length: 0)); tv.scrollRangeToVisible(tv.selectedRange())
        wait(1.5)
        for _ in 0..<8 {
            stall.worst = 0; stall.woke = nil
            tv.insertText(CommandLine.arguments.contains("enter") ? "\n" : "a", replacementRange: tv.selectedRange())
            wait(1.3)
            print("keystroke stall:", String(format: "%.1f ms", stall.worst * 1000), to: &standardError)
        }
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }
    for place in [10, tv.string.utf16.count / 2] {
        tv.setSelectedRange(NSRange(location: place, length: 0)); tv.scrollRangeToVisible(tv.selectedRange())
        measurePause("one keystroke + pause @\(place):") { tv.insertText("a", replacementRange: tv.selectedRange()) }
        measurePause("five keystrokes + pause @\(place):") { for _ in 0..<5 { tv.insertText("b", replacementRange: tv.selectedRange()); wait(0.05) } }
        measurePause("enter + pause @\(place):") { tv.insertText("\n", replacementRange: tv.selectedRange()) }
    }
    measurePause("scroll 30 steps:") {
        let clip = tv.enclosingScrollView!.contentView
        for i in 0..<30 { clip.scroll(to: NSPoint(x: 0, y: CGFloat(i) * 600)); tv.enclosingScrollView!.reflectScrolledClipView(clip); wait(0.016) }
    }
    measurePause("switch to split:") { model.workspace.viewMode = .split }
    measurePause("keystroke + pause in split:") { tv.insertText("c", replacementRange: tv.selectedRange()) }
    if let page = model.workspace.preview {
        page.webView.evaluateJavaScript("document.getElementById('content').textContent.length + ' chars, ' + document.getElementById('content').children.length + ' blocks'") { result, _ in
            print("preview holds:", result ?? "nothing", to: &standardError)
        }
        wait(1)
        let clip = tv.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: tv.frame.height / 3)); tv.enclosingScrollView!.reflectScrolledClipView(clip)
        wait(1)
        page.webView.evaluateJavaScript("[document.scrollingElement.scrollTop, document.scrollingElement.scrollHeight, isSyncing]") { result, _ in
            print("editor at line \(model.workspace.controller.topLine ?? -1): preview scrollTop, height, syncing =", result ?? "nothing", to: &standardError)
        }
        wait(1)
        page.webView.evaluateJavaScript("document.scrollingElement.scrollTop = document.scrollingElement.scrollHeight * 0.6") { _, _ in }
        wait(1)
        print("after scrolling the preview to 60%, editor top line:", model.workspace.controller.topLine ?? -1, "of", model.workspace.controller.lineCount ?? -1, to: &standardError)
        page.webView.callAsyncJavaScript("return await new Promise(function (done) { requestAnimationFrame(function () { done('frame ran'); }); setTimeout(function () { done('no frame in 500 ms'); }, 500); })", in: nil, in: .page) { result in
            print("animation frame:", (try? result.get()) ?? "error", to: &standardError)
            print("window visible:", window.occlusionState.contains(.visible), "app active:", NSApp.isActive, to: &standardError)
        }
        wait(1)
        page.webView.evaluateJavaScript("window.webkit.messageHandlers.scroll.postMessage(lineAtOffset(document.scrollingElement.scrollTop))") { _, _ in }
        wait(1)
        print("after posting directly, editor top line:", model.workspace.controller.topLine ?? -1, to: &standardError)
    } else {
        print("preview page never made", to: &standardError)
    }
    try? FileManager.default.removeItem(at: dir)
    ProcessInfo.processInfo.endActivity(activity)
    exit(0)
}
