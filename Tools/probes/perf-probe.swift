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
    func ms(_ start: CFAbsoluteTime) -> String { String(format: "%.1f ms", (CFAbsoluteTimeGetCurrent() - start) * 1000) }
    let notesURL = dir.appendingPathComponent("notes.json")
    var t = CFAbsoluteTimeGetCurrent()
    let seedStore = NoteStore(notesFile: NotesFile(url: notesURL))
    let paragraph = (1...60).map { "Line \($0) with some **bold** text, a [link](https://example.com) and `code`." }.joined(separator: "\n")
    let count = Int(CommandLine.arguments.dropFirst().first ?? "1000") ?? 1000
    for i in 0..<count { let id = seedStore.createNote(); seedStore.updateBody(id, "# Note \(i)\n" + paragraph) }
    print("seed 1000 notes:", ms(t), to: &standardError)
    t = CFAbsoluteTimeGetCurrent(); _ = seedStore.saveNow(); print("saveNow 1000 notes:", ms(t), to: &standardError)
    let size = (try? FileManager.default.attributesOfItem(atPath: notesURL.path)[.size] as? Int) ?? 0
    print("notes.json size:", size / 1024, "KB", to: &standardError)
    t = CFAbsoluteTimeGetCurrent()
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: notesURL)), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    print("load store + AppModel init:", ms(t), "notes:", model.store.notes.count, to: &standardError)
    let ids = model.store.appNotes.map(\.id)
    for i in stride(from: 0, to: 60, by: 6) { model.groups.addToNewGroup(ids[i]); model.groups.add(ids[i + 1], to: model.groups.list.group(of: ids[i])!.id) }
    let big = model.store.createNote()
    model.store.updateBody(big, "# Big\n" + (1...25_000).map { "Line \($0): some **markdown** with `code` and [link](https://x.y) text here" }.joined(separator: "\n"))
    print("big note chars:", model.store.note(big)!.body.utf16.count, to: &standardError)

    t = CFAbsoluteTimeGetCurrent()
    let window = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingController(rootView: ContentView(model: model))
    host.sceneBridgingOptions = [.toolbars, .title]
    window.contentViewController = host
    window.setFrame(NSRect(x: 40, y: 40, width: 1100, height: 700), display: true)
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
    window.displayIfNeeded()
    print("first window layout (1000 notes, sidebar):", ms(t), to: &standardError)
    model.start()
    wait(0.5)
    print("preview page made at launch in Edit mode:", model.workspace.preview != nil, to: &standardError)
    if CommandLine.arguments.count > 2 {
        var hist: [String: Int] = [:]
        var stack: [NSView] = [window.contentView!.superview!]
        while let v = stack.popLast() { hist[String(describing: type(of: v)), default: 0] += 1; stack += v.subviews }
        for (k, v) in hist.sorted(by: { $0.value > $1.value }).prefix(12) { print(v, k, to: &standardError) }
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }

    func textView() -> CodeTextView? {
        var stack: [NSView] = [window.contentView!]
        while let v = stack.popLast() { if let tv = v as? CodeTextView { return tv }; stack += v.subviews }
        return nil
    }
    t = CFAbsoluteTimeGetCurrent(); model.tabs.open(ids[5]); RunLoop.main.run(until: Date()); window.displayIfNeeded()
    print("switch to small note:", ms(t), to: &standardError)
    wait(0.5)
    for k in 6..<10 {
        t = CFAbsoluteTimeGetCurrent(); model.tabs.open(ids[k * 3]); RunLoop.main.run(until: Date()); window.displayIfNeeded()
        print("switch again:", ms(t), to: &standardError)
        wait(0.4)
    }
    if CommandLine.arguments.count > 1 && CommandLine.arguments[1] != "1000" { try? FileManager.default.removeItem(at: dir); exit(0) }
    wait(0.5)
    t = CFAbsoluteTimeGetCurrent(); model.tabs.open(big); RunLoop.main.run(until: Date()); window.displayIfNeeded()
    print("switch to big note (25k lines):", ms(t), to: &standardError)
    wait(1.5)
    guard let tv = textView() else { print("no text view", to: &standardError); exit(1) }
    window.makeFirstResponder(tv)
    for (label, location) in [("small note", -1), ("big note top", 10), ("big note middle", tv.string.utf16.count / 2), ("big note end", tv.string.utf16.count)] {
        if location == -1 { continue }
        tv.setSelectedRange(NSRange(location: location, length: 0)); tv.scrollRangeToVisible(tv.selectedRange()); wait(0.5)
        var samples: [Double] = []
        for _ in 0..<40 {
            let s = CFAbsoluteTimeGetCurrent()
            tv.insertText("a", replacementRange: tv.selectedRange())
            RunLoop.main.run(until: Date()); window.displayIfNeeded()
            samples.append((CFAbsoluteTimeGetCurrent() - s) * 1000)
            wait(0.03)
        }
        samples.sort()
        print("keystroke \(label): median", String(format: "%.2f", samples[20]), "ms, p95", String(format: "%.2f", samples[37]), "ms, max", String(format: "%.2f", samples[39]), "ms", to: &standardError)
    }
    wait(1.0)
    var settle: [Double] = []
    for _ in 0..<5 { let s = CFAbsoluteTimeGetCurrent(); wait(0.2); settle.append((CFAbsoluteTimeGetCurrent() - s) * 1000 - 200) }
    print("idle overrun after typing (debounced work):", settle.map { String(format: "%.1f", $0) }, to: &standardError)
    model.tabs.open(ids[7], keep: true); wait(0.5); model.tabs.open(big, keep: true); wait(1)
    var tabSwitches: [String] = []
    for k in 0..<8 {
        t = CFAbsoluteTimeGetCurrent(); model.tabs.activate(k.isMultiple(of: 2) ? ids[7] : big); RunLoop.main.run(until: Date()); window.displayIfNeeded()
        tabSwitches.append(ms(t))
        wait(0.4)
    }
    print("switch between open tabs (small, big, …):", tabSwitches, to: &standardError)
    if ProcessInfo.processInfo.environment["PROBE_TABLOOP"] != nil {
        print("READY", to: &standardError)
        for k in 0..<60 { model.tabs.activate(k.isMultiple(of: 2) ? ids[7] : big); wait(0.15) }
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }

    var scroll: [Double] = []
    let clip = tv.enclosingScrollView!.contentView
    for i in 0..<60 {
        let s = CFAbsoluteTimeGetCurrent()
        clip.scroll(to: NSPoint(x: 0, y: CGFloat(i) * 400 + 200_000)); tv.enclosingScrollView!.reflectScrolledClipView(clip)
        RunLoop.main.run(until: Date()); window.displayIfNeeded()
        scroll.append((CFAbsoluteTimeGetCurrent() - s) * 1000)
    }
    scroll.sort()
    print("scroll step big note: median", String(format: "%.2f", scroll[30]), "ms, p95", String(format: "%.2f", scroll[56]), "ms", to: &standardError)

    model.workspace.viewMode = .split; wait(2.0)
    var split: [Double] = []
    tv.setSelectedRange(NSRange(location: 10, length: 0))
    if let tv2 = textView() {
        window.makeFirstResponder(tv2)
        for _ in 0..<30 {
            let s = CFAbsoluteTimeGetCurrent()
            tv2.insertText("b", replacementRange: tv2.selectedRange())
            RunLoop.main.run(until: Date()); window.displayIfNeeded()
            split.append((CFAbsoluteTimeGetCurrent() - s) * 1000)
            wait(0.03)
        }
        split.sort()
        print("keystroke big note in split: median", String(format: "%.2f", split[15]), "ms, p95", String(format: "%.2f", split[28]), "ms", to: &standardError)
        var idle: [Double] = []
        for _ in 0..<5 { let s = CFAbsoluteTimeGetCurrent(); wait(0.3); idle.append((CFAbsoluteTimeGetCurrent() - s) * 1000 - 300) }
        print("idle overrun in split after typing:", idle.map { String(format: "%.1f", $0) }, to: &standardError)
    }
    model.workspace.viewMode = .edit; wait(0.5)

    var frames: [Double] = []
    var dragStart: Double?
    let session = model.sidebar.reorder
    let visible = model.groups.list.rows(for: model.store.appNotes).compactMap { row -> UUID? in
        if case .note(let note, nil) = row, session.frames[note.id] != nil { return note.id }
        return nil
    }
    let dragged = visible[min(4, visible.count - 1)]
    for step in 0...40 {
        let s = CFAbsoluteTimeGetCurrent()
        session.update(dragged, translation: CGSize(width: 0, height: CGFloat(step) * 8), onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) })
        RunLoop.main.run(until: Date()); window.displayIfNeeded()
        let frame = (CFAbsoluteTimeGetCurrent() - s) * 1000
        if dragStart == nil, !session.lifted.isEmpty { dragStart = frame } else if step > 0 { frames.append(frame) }
        wait(0.016)
    }
    print("sidebar drag start (1000 notes):", dragStart.map { String(format: "%.2f ms", $0) } ?? "never lifted", to: &standardError)
    frames.sort()
    print("sidebar drag frame (1000 notes): median", String(format: "%.2f", frames[frames.count / 2]), "ms, p95", String(format: "%.2f", frames[frames.count * 95 / 100]), "ms, lifted:", session.lifted.count, to: &standardError)
    let order = model.store.appNotes.map(\.id)
    t = CFAbsoluteTimeGetCurrent()
    _ = session.end(); RunLoop.main.run(until: Date()); window.displayIfNeeded()
    print("drop:", ms(t), to: &standardError)
    t = CFAbsoluteTimeGetCurrent()
    wait(0.6)
    print("settle + commit overrun:", String(format: "%.1f ms", (CFAbsoluteTimeGetCurrent() - t) * 1000 - 600), to: &standardError)
    print("note moved on drop:", model.store.appNotes.map(\.id) != order, to: &standardError)
    wait(0.6)

    if let scrollView = session.scrollView, let viewport = session.viewport,
       let pressed = model.groups.list.rows(for: model.store.appNotes).lazy.compactMap({ row -> UUID? in
           if case .note(let note, nil) = row, session.frames[note.id] != nil { return note.id }
           return nil
       }).first {
        let before = scrollView.contentView.bounds.origin.y
        let bottom = CGPoint(x: viewport.midX, y: viewport.maxY - 4)
        session.update(pressed, start: CGPoint(x: viewport.midX, y: viewport.minY + 20), location: CGPoint(x: viewport.midX, y: viewport.minY + 20), translation: .zero, onPress: {}, plan: { model.groups.sidebarPlan(lifting: pressed) })
        var gaps: [Double] = []
        var last = CFAbsoluteTimeGetCurrent()
        for _ in 0..<60 {
            session.update(pressed, start: CGPoint(x: viewport.midX, y: viewport.minY + 20), location: bottom, translation: CGSize(width: 0, height: bottom.y - viewport.minY - 20), onPress: {}, plan: { model.groups.sidebarPlan(lifting: pressed) })
            wait(0.016)
            let now = CFAbsoluteTimeGetCurrent(); gaps.append((now - last) * 1000 - 16); last = now
        }
        gaps.sort()
        let scrolled = scrollView.contentView.bounds.origin.y - before
        print("autoscroll near bottom edge: scrolled", String(format: "%.0f pt", scrolled), "in 1 s, translation", String(format: "%.0f", session.translation), "lifted:", session.lifted.count, "frame overrun median", String(format: "%.1f", gaps[30]), "p95", String(format: "%.1f", gaps[57]), "ms", to: &standardError)
        session.cancel(); wait(0.4)
        print("autoscroll stops after cancel:", abs(scrollView.contentView.bounds.origin.y - before - scrolled) < 1 || { let y = scrollView.contentView.bounds.origin.y; wait(0.2); return scrollView.contentView.bounds.origin.y == y }(), to: &standardError)
    } else {
        print("autoscroll: no scroll view or viewport reached the session", to: &standardError)
    }
    @MainActor final class Busy { var woke: CFAbsoluteTime?; var worst = 0.0; var spans: [(at: CFAbsoluteTime, length: Double)] = [] }
    let busy = Busy()
    let busyObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, activity in
        MainActor.assumeIsolated {
            let now = CFAbsoluteTimeGetCurrent()
            if activity == .afterWaiting { busy.woke = now } else if let woke = busy.woke { busy.worst = max(busy.worst, now - woke); busy.woke = nil; if now - woke > 0.008 { busy.spans.append((woke, now - woke)) } }
        }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), busyObserver, .commonModes)
    model.openGlobalSearch()
    wait(0.5)
    if ProcessInfo.processInfo.environment["PROBE_SEARCHLOOP"] != nil {
        print("READY", to: &standardError)
        var renders: [Double] = []
        for i in 0..<30 {
            let fresh = ProcessInfo.processInfo.environment["PROBE_SEARCHLOOP"] == "fresh"
            if fresh, i % 2 == 1 { model.globalSearch.query = ""; wait(0.4); continue }
            model.globalSearch.query = i % 2 == 0 ? "Note 99" : "Note 98"
            wait(0.12)
            busy.worst = 0; busy.woke = nil
            wait(0.28)
            if i >= 10 { renders.append(busy.worst * 1000) }
        }
        renders.sort()
        print("global search result render (\(renders.count) runs): median", String(format: "%.1f", renders[renders.count / 2]), "ms, worst", String(format: "%.1f", renders[renders.count - 1]), "ms", to: &standardError)
        try? FileManager.default.removeItem(at: dir)
        exit(0)
    }
    for query in ["zebra", "Note 99", "Note 98", "Note 97"] {
        model.globalSearch.query = ""
        wait(0.5)
        busy.worst = 0; busy.woke = nil; busy.spans = []
        for length in 1...query.count {
            model.globalSearch.query = String(query.prefix(length))
            wait(0.08)
        }
        let typed = CFAbsoluteTimeGetCurrent()
        let typingWorst = busy.worst
        var shown: Double?
        while CFAbsoluteTimeGetCurrent() - typed < 3 {
            wait(0.005)
            if query != "zebra", model.globalSearch.results.count == 11 {
                shown = (CFAbsoluteTimeGetCurrent() - typed) * 1000
                break
            }
        }
        wait(0.5)
        print("global search typing \"\(query)\" (1000 notes): worst stall while typing", String(format: "%.1f ms", typingWorst * 1000), "overall", String(format: "%.1f ms", busy.worst * 1000), "results after last key:", shown.map { String(format: "%.0f ms", $0) } ?? "never", "notes:", model.globalSearch.results.count, "spans > 8 ms after last key:", busy.spans.filter { $0.at > typed }.map { String(format: "%.0f ms at +%.0f", $0.length * 1000, ($0.at - typed) * 1000) }, to: &standardError)
    }
    model.closeGlobalSearch()
    wait(0.3)
    model.quickOpen.show()
    wait(0.6)
    window.acceptsMouseMovedEvents = true
    var hoverSpans: [Double] = []
    var overList = 0
    for step in 0..<40 {
        busy.worst = 0; busy.woke = nil
        send(.mouseMoved, window, CGPoint(x: 700, y: 70 + CGFloat(step) * 10))
        wait(0.02)
        hoverSpans.append(busy.worst * 1000)
        if NSCursor.current == NSCursor.pointingHand { overList += 1 }
    }
    hoverSpans.sort()
    print("quick open hover (1000 notes): median", String(format: "%.2f", hoverSpans[20]), "ms, p95", String(format: "%.2f", hoverSpans[37]), "ms, max", String(format: "%.2f", hoverSpans[39]), "ms, moves over the list:", overList, to: &standardError)
    model.quickOpen.close()
    wait(0.3)
    t = CFAbsoluteTimeGetCurrent(); _ = model.flushAll(); print("flushAll (quit save):", ms(t), to: &standardError)
    t = CFAbsoluteTimeGetCurrent(); _ = model.flushAll(); print("flushAll (no changes):", ms(t), to: &standardError)
    try? FileManager.default.removeItem(at: dir)
    exit(0)
}
