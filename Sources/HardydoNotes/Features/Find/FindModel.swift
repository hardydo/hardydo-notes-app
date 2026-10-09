import Foundation
import HardydoNotesCore
import Observation

/// What the matches were found for; a change to any of it means searching again.
struct FindInputs: Equatable, Sendable {
    let note: Note.ID
    let revision: Int
    let query: String
    let options: SearchOptions
}

/// The find bar of the open note. Its matches are found off the main thread, so they always say what they were found for.
@MainActor
@Observable
final class FindModel {
    static let typingPause = Duration.milliseconds(100)
    var isShown = false
    var showsReplace = false
    var query = ""
    var replaceText = ""
    var current: NSRange?
    var focusRequest = 0
    /// Shared by find and the search of every note.
    private(set) var options = SearchOptions()
    private(set) var ranges: [NSRange] = []
    private(set) var error: String?
    @ObservationIgnored private var searched: FindInputs?
    @ObservationIgnored private var running: (inputs: FindInputs, task: Task<[NSRange]?, Never>)?
    @ObservationIgnored private var lastAction: Task<Void, Never>?
    @ObservationIgnored private var pendingQuery: (location: Int, task: Task<Void, Never>)?
    private let editor: WorkspaceEditor
    private let store: NoteStore

    init(editor: WorkspaceEditor, store: NoteStore) {
        self.editor = editor
        self.store = store
    }

    var currentIndex: Int? {
        current.flatMap { ranges.firstIndex(of: $0) }
    }

    func isCurrent(_ inputs: FindInputs) -> Bool {
        searched == inputs
    }

    /// Callers that act on the matches await this, so Return right after typing never jumps to a match of the old query.
    func search(_ inputs: FindInputs, in text: String) async {
        guard searched != inputs else { return }
        let task: Task<[NSRange]?, Never>
        if let running, running.inputs == inputs {
            task = running.task
        } else {
            running?.task.cancel()
            task = Task.detached(priority: .userInitiated) { TextSearch.ranges(of: inputs.query, options: inputs.options, in: text) }
            running = (inputs, task)
        }
        let found = await task.value
        guard running?.inputs == inputs else { return }
        running = nil
        searched = inputs
        ranges = found ?? []
        error = found == nil ? "Invalid regular expression" : nil
    }

    /// Runs moves between matches one after another, in the order they were asked for, each once its search is done.
    func perform(_ action: @escaping @MainActor () async -> Void) {
        let previous = lastAction
        lastAction = Task {
            await previous?.value
            await action()
        }
    }

    var inputs: FindInputs? {
        guard let note = editor.note else { return nil }
        return FindInputs(note: note.id, revision: store.revision(of: note.id), query: query, options: options)
    }

    /// Brings the matches up to date with the open note; true when they are, false when something newer took over.
    @discardableResult
    func refresh() async -> Bool {
        guard isShown, let note = editor.note, let inputs else { return false }
        await search(inputs, in: note.body)
        return self.inputs.map(isCurrent) ?? false
    }

    func open(replace: Bool = false) {
        let controller = editor.controller
        controller.commit()
        guard editor.note != nil else { return }
        editor.leavePreview(to: .split)
        if let selected = controller.selectedText, !selected.contains(where: \.isNewline), selected.count <= 200 {
            query = selected
        }
        isShown = true
        if replace { showsReplace = true }
        focusRequest += 1
        selectMatch(atOrAfter: controller.selectedRange?.location ?? 0)
    }

    func close() {
        isShown = false
        current = nil
        dropPendingQuery()
        running?.task.cancel()
        running = nil
        editor.controller.focus()
    }

    /*
     The field also hands back its unchanged text, on focus for one, which must not move the selection. Typing
     searches once a key pause; anything that acts on the matches runs the waiting search first.
     */
    func setQuery(_ query: String) {
        guard query != self.query else { return }
        self.query = query
        let location = pendingQuery?.location ?? editor.controller.selectedRange?.location ?? 0
        pendingQuery?.task.cancel()
        pendingQuery = (location, Task { [weak self] in
            try? await Task.sleep(for: Self.typingPause)
            guard !Task.isCancelled else { return }
            self?.runPendingQuery()
        })
    }

    private func runPendingQuery() {
        guard let pending = pendingQuery else { return }
        dropPendingQuery()
        selectMatch(atOrAfter: pending.location)
    }

    private func dropPendingQuery() {
        pendingQuery?.task.cancel()
        pendingQuery = nil
    }

    func setOptions(_ options: SearchOptions) {
        let location = pendingQuery?.location ?? editor.controller.selectedRange?.location ?? 0
        dropPendingQuery()
        self.options = options
        if isShown { selectMatch(atOrAfter: location) }
    }

    func next(forward: Bool = true) {
        editor.controller.commit()
        guard isShown else { return open() }
        runPendingQuery()
        perform { [self] in
            guard await refresh() else { return }
            let selected = editor.controller.selectedRange ?? NSRange(location: 0, length: 0)
            if let target = TextSearch.nextMatch(in: ranges, from: selected, forward: forward) { show(target) }
        }
    }

    private func selectMatch(atOrAfter location: Int) {
        perform { [self] in
            guard await refresh() else { return }
            guard let target = TextSearch.firstMatch(in: ranges, atOrAfter: location) else {
                current = nil
                return
            }
            show(target)
        }
    }

    private func show(_ range: NSRange) {
        current = range
        editor.controller.reveal(range)
    }

    var canReplace: Bool {
        editor.canEditText && !ranges.isEmpty
    }

    func replaceCurrent() {
        let controller = editor.controller
        controller.commit()
        runPendingQuery()
        perform { [self] in
            guard await refresh(), canReplace, let note = editor.note,
                  let expression = try? TextSearch.expression(for: query, options: options) else { return }
            guard let range = current, ranges.contains(range) else { return next() }
            guard let replacement = TextSearch.replacement(for: range, in: note.body, expression: expression, template: replaceText, options: options),
                  controller.replace(range, with: replacement) else { return }
            controller.commit()
            selectMatch(atOrAfter: range.location + (replacement as NSString).length)
        }
    }

    func replaceAll() {
        let controller = editor.controller
        controller.commit()
        runPendingQuery()
        perform { [self] in
            guard await refresh(), canReplace, let note = editor.note,
                  let expression = try? TextSearch.expression(for: query, options: options) else { return }
            let result = TextSearch.replacingAll(in: note.body, expression: expression, template: replaceText, options: options)
            guard result.count > 0, controller.replaceAll(with: result.text) else { return }
            controller.commit()
            current = nil
        }
    }
}
