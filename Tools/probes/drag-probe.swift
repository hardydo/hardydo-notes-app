import AppKit
import HardydoNotesCore
import SwiftUI

/*
 Usage: run-probe.sh drag-probe.swift [audit | top | shot <dir>]
 Drags every note through the whole sidebar and reports any gap, or half of a gap, it could not reach; `top` puts a
 group first. `shot` saves the lifted row passing its neighbours and two drops, ending with one below the last group.
 */
final class ProbeWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor
func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor
func render(_ window: NSWindow, _ file: String) {
    let view = window.contentView!.superview!
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.finishLaunching()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("probe-dragsweep-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    let notesURL = dir.appendingPathComponent("notes.json")
    let seed = NoteStore(notesFile: NotesFile(url: notesURL))
    for i in (0..<8).reversed() { let id = seed.createNote(); seed.updateBody(id, "# N\(i)\nbody") }
    _ = seed.saveNow()
    let model = AppModel(store: NoteStore(notesFile: NotesFile(url: notesURL)), groupsFile: JSONFile(url: dir.appendingPathComponent("groups.json")), preferences: Preferences(defaults: defaults))
    let ids = model.store.appNotes.map(\.id)
    let name = { @MainActor (id: UUID) -> String in
        if let note = model.store.note(id) { return String(note.body.prefix(4).dropFirst(2)) }
        return model.groups.list.group(id).map { "[\($0.displayName)]" } ?? "?"
    }
    let mode = CommandLine.arguments.dropFirst().first ?? "audit"
    let first = mode == "top" ? 0 : 2
    model.groups.addToNewGroup(ids[first]); model.groups.add(ids[first + 1], to: model.groups.list.group(of: ids[first])!.id)
    model.groups.rename(model.groups.list.group(of: ids[first])!.id, to: "G1")
    model.groups.addToNewGroup(ids[6]); model.groups.add(ids[7], to: model.groups.list.group(of: ids[6])!.id)
    model.groups.rename(model.groups.list.group(of: ids[6])!.id, to: "G2")

    let window = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    let host = NSHostingController(rootView: ContentView(model: model))
    host.sceneBridgingOptions = [.toolbars, .title]
    window.contentViewController = host
    window.setFrame(NSRect(x: 40, y: 40, width: 900, height: 700), display: true)
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
    window.displayIfNeeded()
    model.start()
    wait(0.6)

    @MainActor func listing() -> String {
        model.groups.list.rows(for: model.store.appNotes).map { row in
            switch row {
            case .header(let group): "[\(group.displayName)]"
            case .note(let note, let group): group == nil ? name(note.id) : "  " + name(note.id)
            }
        }.joined(separator: " ")
    }
    print("rows:", listing())
    let session = model.sidebar.reorder

    @MainActor func dropAt(_ dragged: UUID, path: [CGFloat], snapshot: String? = nil) {
        session.update(dragged, translation: .zero, onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) })
        for value in path {
            session.update(dragged, translation: CGSize(width: 0, height: value), onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) })
            RunLoop.main.run(until: Date()); wait(0.01)
        }
        wait(0.3)
        if let snapshot { window.displayIfNeeded(); render(window, snapshot) }
        _ = session.end()
        wait(0.6)
        print("after dropping \(name(dragged)) at t\(Int(path.last ?? 0)):", listing())
    }

    @MainActor func reached(_ dragged: UUID, to limit: CGFloat) -> Set<String> {
        var seen: Set<String> = []
        let step: CGFloat = limit < 0 ? -1 : 1
        session.update(dragged, translation: .zero, onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) })
        var value: CGFloat = 0
        while abs(value) <= abs(limit) {
            session.update(dragged, translation: CGSize(width: 0, height: value), onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) })
            if let landing = session.landing { seen.insert("\(Int(landing.offset))/\(landing.lane.map(name) ?? "-")") }
            value += step
        }
        session.cancel()
        _ = session.end()
        wait(0.3)
        return seen
    }
    @MainActor func audit() {
        let notes = model.groups.list.rows(for: model.store.appNotes).compactMap { row -> UUID? in
            if case .note(let note, _) = row { return note.id }
            return nil
        }
        var missing = 0
        for dragged in notes {
            guard let plan = model.groups.sidebarPlan(lifting: dragged) else { continue }
            let remaining = plan.rows.filter { !plan.block.contains($0) }
            let origin = session.frames[plan.rows[0]]!.minY
            let lead = session.frames[dragged]!.minY
            var prefix: CGFloat = 0
            var expected: Set<String> = []
            for index in 0...remaining.count {
                for upper in [false, true] where plan.isSlot(index, upper) {
                    expected.insert("\(Int(origin + prefix - lead))/\(plan.lane(.slot(index, upper: upper)).map(name) ?? "-")")
                }
                if index < remaining.count { prefix += session.frames[remaining[index]]!.height }
            }
            let got = reached(dragged, to: -700).union(reached(dragged, to: 700))
            let lost = expected.subtracting(got)
            if !lost.isEmpty { missing += lost.count; print("  \(name(dragged)) cannot reach:", lost.sorted()) }
        }
        print("audit:", missing == 0 ? "every slot reachable" : "\(missing) slots unreachable")
    }
    if mode == "audit" || mode == "top" {
        audit()
    } else {
        let out = CommandLine.arguments.dropFirst(2).first ?? dir.path
        @MainActor func hold(_ dragged: UUID, at value: CGFloat, _ file: String) {
            session.update(dragged, translation: .zero, onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) })
            for step in 0...10 { session.update(dragged, translation: CGSize(width: 0, height: value * CGFloat(step) / 10), onPress: {}, plan: { model.groups.sidebarPlan(lifting: dragged) }); wait(0.02) }
            wait(0.4); window.displayIfNeeded(); render(window, out + "/" + file)
            session.cancel(); wait(0.5)
        }
        hold(ids[0], at: 22, "over-next.png")
        hold(ids[4], at: -22, "over-previous.png")
        hold(ids[2], at: 22, "group-note-down.png")
        let down = (0...60).map { CGFloat($0) * 5 }
        dropAt(ids[0], path: down + [600], snapshot: out + "/lifted-down.png")
        dropAt(ids[5], path: (0...40).map { -CGFloat($0) * 3 }, snapshot: out + "/lifted-up.png")
    }
    try? FileManager.default.removeItem(at: dir)
    exit(0)
}
