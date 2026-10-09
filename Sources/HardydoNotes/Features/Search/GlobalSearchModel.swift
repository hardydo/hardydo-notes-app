import Foundation
import HardydoNotesCore
import Observation

/// Every note searched for one query, off the main thread and once typing pauses.
@MainActor
@Observable
final class GlobalSearchModel {
    var isShown = false
    var query = "" {
        didSet { if query != oldValue, !collapsed.isEmpty { collapsed = [] } }
    }
    var collapsed: Set<Note.ID> = []
    var focusRequest = 0
    private(set) var results: [NoteMatches] = []
    private(set) var matchCount = 0
    private(set) var error: String?
    @ObservationIgnored private var memo = SearchMemo(query: "", options: SearchOptions())

    /// Run from a task that restarts on every change, so a newer query or edit cancels the search in flight.
    func search(_ notes: [SearchableNote], options: SearchOptions) async {
        let query = query
        let problem = options.regex && !query.isEmpty && (try? TextSearch.expression(for: query, options: options)) == nil ? "Invalid regular expression" : nil
        if error != problem { error = problem }
        guard !query.isEmpty, error == nil else { return publish([]) }
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        let memo = memo
        let search = Task.detached(priority: .userInitiated) { () -> (results: [NoteMatches], memo: SearchMemo)? in
            var memo = memo
            return TextSearch.searchAll(notes, query: query, options: options, memo: &memo).map { ($0, memo) }
        }
        let outcome = await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
        guard let outcome, !Task.isCancelled else { return }
        self.memo = outcome.memo
        publish(outcome.results)
    }

    private func publish(_ found: [NoteMatches]) {
        guard found != results else { return }
        results = found
        matchCount = found.reduce(0) { $0 + $1.lines.count }
    }
}
