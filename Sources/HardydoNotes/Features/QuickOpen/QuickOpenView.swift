import HardydoNotesCore
import SwiftUI

/// VS Code's Quick Open: ⌘P finds a note by name, and a leading ":" (or ⌃G) jumps to a line instead.
struct QuickOpenState {
    var query = ""
    var highlighted = 0
    var fieldFrame = CGRect.zero
    var listFrame = CGRect.zero
}

struct QuickOpenView: View {
    let quickOpen: QuickOpenModel
    let actions: QuickOpenActions
    let mode: QuickOpenMode
    let width: CGFloat
    @StateObject private var state = ViewState(QuickOpenState())
    /// Ranked when the query changes, not on every redraw: the cursor, hover and arrow keys all read it.
    @StateObject private var matches = ViewState<[NoteSummary]>([])
    @StateObject private var frame = ViewState(CGRect.zero)
    @StateObject private var unwatch = ViewState<[() -> Void]>([])
    @FocusState private var isFocused: Bool
    private static let limit = 200
    fileprivate static let rowHeight: CGFloat = 30
    private static let visibleRows: CGFloat = 12
    nonisolated private static let space = "quickOpen"

    private var isLineMode: Bool { state.value.query.hasPrefix(":") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(mode == .line ? "Go to line" : "Search notes by name (type : to go to a line)", text: $state.value.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .focused($isFocused)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { state.value.fieldFrame = $0 }
                .onSubmit(submit)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onExitCommand { quickOpen.close() }
            Divider()
            if isLineMode {
                Text(lineHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if matches.value.isEmpty {
                Text("No matching notes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                let matches = matches.value
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, note in
                                QuickOpenRow(note: note, place: actions.place(note), isHighlighted: index == state.value.highlighted)
                                    .onTapGesture { open(note) }
                            }
                        }
                        .padding(4)
                    }
                    .frame(height: min(CGFloat(matches.count), Self.visibleRows) * Self.rowHeight + 8)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { state.value.listFrame = $0 }
                    .onChange(of: state.value.highlighted) { _, index in
                        if matches.indices.contains(index) { proxy.scrollTo(matches[index].id) }
                    }
                }
            }
        }
        .frame(width: width)
        .coordinateSpace(.named(Self.space))
        .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
            if case .active(let point) = phase { cursor(at: point).set() }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.value = $0 }
        .padding(.top, 10)
        .onAppear {
            isFocused = true
            watchOutside()
        }
        .onDisappear(perform: stopWatching)
        // The palette stays up when ⌃G follows ⌘P, so the mode's starting text is set on every change of mode.
        .onChange(of: mode, initial: true) { state.value.query = mode == .line ? ":" : "" }
        .onChange(of: state.value.query, initial: true) {
            state.value.highlighted = 0
            matches.value = isLineMode ? [] : Array(actions.notes(state.value.query).prefix(Self.limit))
        }
    }

    // Set on every move, and from one place: the editor underneath keeps putting its own text cursor back.
    private func cursor(at point: CGPoint) -> NSCursor {
        if state.value.fieldFrame.contains(point) { return .iBeam }
        if !isLineMode, !matches.value.isEmpty, state.value.listFrame.contains(point) { return .pointingHand }
        return .arrow
    }

    private var lineHint: String {
        let count = actions.lineCount()
        guard count > 0 else { return "Open a note to go to a line." }
        if let line = Int(state.value.query.dropFirst()) { return "Go to line \(min(max(line, 1), count)), then press Return." }
        return "Type a line number between 1 and \(count)."
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        let count = matches.value.count
        guard count > 0 else { return .ignored }
        state.value.highlighted = (state.value.highlighted + offset + count) % count
        return .handled
    }

    private func submit() {
        if isLineMode {
            guard let line = Int(state.value.query.dropFirst()), actions.lineCount() > 0 else { return }
            quickOpen.dismiss()
            actions.goToLine(line)
        } else if matches.value.indices.contains(state.value.highlighted) {
            open(matches.value[state.value.highlighted])
        }
    }

    /*
     As in VS Code, anything done elsewhere closes the palette: a click outside it (which still lands), the shortcut
     of another command, the menu bar, or leaving the window.
     */
    private func watchOutside() {
        stopWatching()
        let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [quickOpen, frame] event in
            MainActor.assumeIsolated {
                guard let content = event.window?.contentView else { return }
                let location = event.locationInWindow
                if !frame.value.contains(CGPoint(x: location.x, y: content.bounds.height - location.y)) { quickOpen.close() }
            }
            return event
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [quickOpen] event in
            if Self.isOtherCommand(event) { MainActor.assumeIsolated { Self.close(quickOpen, after: event) } }
            return event
        }
        let center = NotificationCenter.default
        let menuBar = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [quickOpen] note in
            let menu = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                if menu != nil, menu == NSApp.mainMenu.map(ObjectIdentifier.init) { quickOpen.close() }
            }
        }
        let windows = center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [quickOpen] _ in
            MainActor.assumeIsolated { quickOpen.close() }
        }
        unwatch.value = [clicks, keys].compactMap { $0 }.map { monitor in { NSEvent.removeMonitor(monitor) } }
            + [menuBar, windows].map { observer in { center.removeObserver(observer) } }
    }

    private func stopWatching() {
        unwatch.value.forEach { $0() }
        unwatch.value = []
    }

    // ⌘P stays with the palette, and the editing and caret shortcuts with its text field.
    nonisolated private static func isOtherCommand(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        return !["p", "a", "c", "v", "x", "z"].contains(key) && ![51, 117, 123, 124, 125, 126].contains(event.keyCode)
    }

    // Closes once the command has run, so it still sees the palette focused; the editor takes focus back unless the command moved it.
    private static func close(_ quickOpen: QuickOpenModel, after event: NSEvent) {
        let window = event.window
        let responder = window?.firstResponder
        DispatchQueue.main.async {
            guard quickOpen.mode != nil else { return }
            if window?.firstResponder === responder { quickOpen.close() } else { quickOpen.dismiss() }
        }
    }

    private func open(_ note: NoteSummary) {
        quickOpen.dismiss()
        actions.open(note.id)
    }
}

/// Hover stays inside the row, so moving the pointer over the list redraws one row at a time.
private struct QuickOpenRow: View {
    let note: NoteSummary
    /// The folder of an opened file, or the group of a note.
    let place: String?
    let isHighlighted: Bool
    @StateObject private var hover = ViewState(false)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: note.filePath != nil ? "doc" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(note.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let place {
                Text(place)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(note.filePath != nil ? .head : .tail)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: QuickOpenView.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
        .contentShape(Rectangle())
        .onHover { hover.value = $0 }
    }

    private var fill: Color {
        if isHighlighted { return Color.accentColor.opacity(0.22) }
        return hover.value ? Color.primary.opacity(0.07) : .clear
    }
}
