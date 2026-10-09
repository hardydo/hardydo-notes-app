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
    var isShown = false
    var showsReplace = false
    var query = ""
    var replaceText = ""
    var current: NSRange?
    var focusRequest = 0
    private(set) var ranges: [NSRange] = []
    private(set) var error: String?
    @ObservationIgnored private var searched: FindInputs?
    @ObservationIgnored private var running: (inputs: FindInputs, task: Task<[NSRange]?, Never>)?
    @ObservationIgnored private var lastAction: Task<Void, Never>?

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

    func close() {
        isShown = false
        current = nil
        running?.task.cancel()
        running = nil
    }
}
