import AppKit
import HardydoNotesCore

struct FindKey: Equatable {
    let note: Note.ID
    let modifiedAt: Date
    let length: Int
    let query: String
    let options: SearchOptions
}

struct FindResult {
    var ranges: [NSRange] = []
    var error: String?
}

struct GlobalKey: Equatable {
    let query: String
    let options: SearchOptions
    let notes: [Note.ID]
    let stamps: [Date]
}

struct GlobalResult: Identifiable {
    let id: Note.ID
    let title: String
    let isFile: Bool
    let lines: [LineMatch]
    let isClipped: Bool
}

extension AppModel {
    var findResult: FindResult {
        guard showFind, let note = selectedNote else { return FindResult() }
        let key = FindKey(note: note.id, modifiedAt: note.modifiedAt, length: note.body.utf16.count, query: findQuery, options: findOptions)
        if let findMemo, findMemo.key == key { return findMemo.result }
        var result = FindResult()
        do {
            if let expression = try TextSearch.expression(for: findQuery, options: findOptions) {
                result.ranges = TextSearch.matches(of: expression, in: note.body)
            }
        } catch {
            result.error = "Invalid regular expression"
        }
        findMemo = (key, result)
        return result
    }

    var findCurrentIndex: Int? {
        findCurrent.flatMap { findResult.ranges.firstIndex(of: $0) }
    }

    func openFind(replace: Bool = false) {
        editor.commit()
        guard selectedNote != nil else { return }
        if viewMode == .preview { viewMode = .split }
        if let selected = editor.selectedText, !selected.contains(where: \.isNewline), selected.count <= 200 {
            findQuery = selected
        }
        showFind = true
        if replace { showReplace = true }
        findFocusRequest += 1
        selectMatch(atOrAfter: editor.selectedRange?.location ?? 0)
    }

    func closeFind() {
        showFind = false
        findCurrent = nil
        editor.focus()
    }

    func setFindQuery(_ query: String) {
        findQuery = query
        selectMatch(atOrAfter: editor.selectedRange?.location ?? 0)
    }

    func setFindOptions(_ options: SearchOptions) {
        findOptions = options
        if showFind { selectMatch(atOrAfter: editor.selectedRange?.location ?? 0) }
    }

    func findNext(forward: Bool = true) {
        editor.commit()
        if !showFind {
            openFind()
            return
        }
        let ranges = findResult.ranges
        guard !ranges.isEmpty else { return }
        let selected = editor.selectedRange ?? NSRange(location: 0, length: 0)
        let target = forward
            ? ranges.first { $0.location > selected.location || ($0.location == selected.location && selected.length == 0) } ?? ranges[0]
            : ranges.last { $0.location < selected.location } ?? ranges[ranges.count - 1]
        show(target)
    }

    private func selectMatch(atOrAfter location: Int) {
        let ranges = findResult.ranges
        guard let target = ranges.first(where: { $0.location >= location }) ?? ranges.first else {
            findCurrent = nil
            return
        }
        show(target)
    }

    private func show(_ range: NSRange) {
        findCurrent = range
        editor.reveal(range)
    }

    var canReplace: Bool {
        selectedNote?.isLocked == false && !findResult.ranges.isEmpty && viewMode != .preview
    }

    func replaceCurrent() {
        editor.commit()
        guard canReplace, let note = selectedNote,
              let expression = try? TextSearch.expression(for: findQuery, options: findOptions) else { return }
        guard let range = findCurrent, findResult.ranges.contains(range) else {
            findNext()
            return
        }
        guard let replacement = TextSearch.replacement(for: range, in: note.body, expression: expression, template: replaceText, options: findOptions),
              editor.replace(range, with: replacement) else { return }
        editor.commit()
        selectMatch(atOrAfter: range.location + (replacement as NSString).length)
    }

    func replaceAll() {
        editor.commit()
        guard canReplace, let note = selectedNote,
              let expression = try? TextSearch.expression(for: findQuery, options: findOptions) else { return }
        let result = TextSearch.replacingAll(in: note.body, expression: expression, template: replaceText, options: findOptions)
        guard result.count > 0, editor.replaceAll(with: result.text) else { return }
        editor.commit()
        findCurrent = nil
    }

    func openGlobalSearch() {
        editor.commit()
        isSearchingAll = true
        searchFocusRequest += 1
    }

    func toggleGlobalSearch() {
        if isSearchingAll {
            closeGlobalSearch()
        } else {
            openGlobalSearch()
        }
    }

    func closeGlobalSearch() {
        isSearchingAll = false
    }

    var globalSearchError: String? {
        guard findOptions.regex else { return nil }
        return (try? TextSearch.expression(for: globalQuery, options: findOptions)) == nil && !globalQuery.isEmpty ? "Invalid regular expression" : nil
    }

    var globalResults: [GlobalResult] {
        let notes = store.notes
        let key = GlobalKey(query: globalQuery, options: findOptions, notes: notes.map(\.id), stamps: notes.map(\.modifiedAt))
        if let globalMemo, globalMemo.key == key { return globalMemo.results }
        var results: [GlobalResult] = []
        if let expression = try? TextSearch.expression(for: globalQuery, options: findOptions) {
            let perNote = 50
            var budget = 2000
            for note in notes where budget > 0 {
                let lines = TextSearch.lineMatches(of: expression, in: note.body, limit: min(perNote + 1, budget))
                guard !lines.isEmpty else { continue }
                budget -= lines.count
                results.append(GlobalResult(
                    id: note.id,
                    title: note.title,
                    isFile: note.localFile != nil,
                    lines: Array(lines.prefix(perNote)),
                    isClipped: lines.count > perNote
                ))
            }
        }
        globalMemo = (key, results)
        return results
    }

    var globalMatchCount: Int {
        globalResults.reduce(0) { $0 + $1.lines.count }
    }

    func openResult(_ note: Note.ID, _ match: LineMatch) {
        findQuery = globalQuery
        showFind = true
        let editorShown = viewMode != .preview && selection == note && editor.textView != nil
        if viewMode == .preview { viewMode = .split }
        selectNote(note)
        findCurrent = match.range
        if editorShown {
            editor.reveal(match.range)
        } else {
            editor.pendingReveal = match.range
        }
    }
}
