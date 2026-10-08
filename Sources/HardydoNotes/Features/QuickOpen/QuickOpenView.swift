import HardydoNotesCore
import SwiftUI

/// VS Code's Quick Open: ⌘P finds a note by name, and a leading ":" (or ⌃G) jumps to a line instead.
struct QuickOpenState {
    var query = ""
    var highlighted = 0
    var hovered: Note.ID?
    var fieldFrame = CGRect.zero
    var listFrame = CGRect.zero
}

struct QuickOpenView: View {
    let model: AppModel
    let mode: QuickOpenMode
    let width: CGFloat
    @StateObject private var state = ViewState(QuickOpenState())
    @StateObject private var frame = ViewState(CGRect.zero)
    @StateObject private var unwatch = ViewState<[() -> Void]>([])
    @FocusState private var isFocused: Bool
    private static let limit = 200
    private static let rowHeight: CGFloat = 30
    private static let visibleRows: CGFloat = 12
    nonisolated private static let space = "quickOpen"

    private var isLineMode: Bool { state.value.query.hasPrefix(":") }

    private var matches: [Note] {
        isLineMode ? [] : Array(model.quickOpenNotes(matching: state.value.query).prefix(Self.limit))
    }

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
                .onExitCommand { model.closeQuickOpen() }
            Divider()
            if isLineMode {
                Text(lineHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if matches.isEmpty {
                Text("No matching notes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                let matches = matches
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, note in
                                row(note, isHighlighted: index == state.value.highlighted)
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
            state.value.query = mode == .line ? ":" : ""
            isFocused = true
            watchOutside()
        }
        .onDisappear(perform: stopWatching)
        .onChange(of: state.value.query) { state.value.highlighted = 0 }
    }

    private func row(_ note: Note, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: note.localFile != nil ? "doc" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(note.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let path = note.localFile?.path {
                Text((path as NSString).deletingLastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else if let group = model.groups.group(of: note.id) {
                Text(group.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(rowFill(note, isHighlighted: isHighlighted)))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { state.value.hovered = note.id } else if state.value.hovered == note.id { state.value.hovered = nil }
        }
    }

    // Set on every move, and from one place: the editor underneath keeps putting its own text cursor back.
    private func cursor(at point: CGPoint) -> NSCursor {
        if state.value.fieldFrame.contains(point) { return .iBeam }
        if !isLineMode, !matches.isEmpty, state.value.listFrame.contains(point) { return .pointingHand }
        return .arrow
    }

    private func rowFill(_ note: Note, isHighlighted: Bool) -> Color {
        if isHighlighted { return Color.accentColor.opacity(0.22) }
        return state.value.hovered == note.id ? Color.primary.opacity(0.07) : .clear
    }

    private var lineHint: String {
        let count = model.selectedLineCount
        guard count > 0 else { return "Open a note to go to a line." }
        if let line = Int(state.value.query.dropFirst()) { return "Go to line \(min(max(line, 1), count)), then press Return." }
        return "Type a line number between 1 and \(count)."
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard !matches.isEmpty else { return .ignored }
        state.value.highlighted = (state.value.highlighted + offset + matches.count) % matches.count
        return .handled
    }

    private func submit() {
        if isLineMode {
            guard let line = Int(state.value.query.dropFirst()), model.selectedLineCount > 0 else { return }
            if model.viewMode == .preview { model.viewMode = .edit }
            model.quickOpen = nil
            model.goToLine(line)
        } else if matches.indices.contains(state.value.highlighted) {
            open(matches[state.value.highlighted])
        }
    }

    /*
     As in VS Code, anything done elsewhere closes the palette: a click outside it (which still lands), the shortcut
     of another command, the menu bar, or leaving the window.
     */
    private func watchOutside() {
        let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [model, frame] event in
            MainActor.assumeIsolated {
                guard let content = event.window?.contentView else { return }
                let location = event.locationInWindow
                if !frame.value.contains(CGPoint(x: location.x, y: content.bounds.height - location.y)) { model.closeQuickOpen() }
            }
            return event
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            if Self.isOtherCommand(event) { MainActor.assumeIsolated { Self.close(model, after: event) } }
            return event
        }
        let center = NotificationCenter.default
        let menuBar = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [model] note in
            let menu = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                if menu != nil, menu == NSApp.mainMenu.map(ObjectIdentifier.init) { model.closeQuickOpen() }
            }
        }
        let windows = center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model.closeQuickOpen() }
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
    private static func close(_ model: AppModel, after event: NSEvent) {
        let window = event.window
        let responder = window?.firstResponder
        DispatchQueue.main.async {
            guard model.quickOpen != nil else { return }
            if window?.firstResponder === responder { model.closeQuickOpen() } else { model.quickOpen = nil }
        }
    }

    private func open(_ note: Note) {
        model.quickOpen = nil
        model.selectNote(note.id)
    }
}
