import Foundation
import HardydoNotesCore
import Testing

private func note(_ index: Int, matches: Int, revision: Int = 1, word: String = "hit") -> SearchableNote {
    SearchableNote(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!, revision: revision, title: "Note \(index)", isFile: false,
                   body: (0..<matches).map { "line \($0) \(word)" }.joined(separator: "\n"))
}

private func ranges(_ query: String, _ text: String, _ options: SearchOptions = SearchOptions()) -> [String] {
    guard let expression = try? TextSearch.expression(for: query, options: options) else { return ["<invalid>"] }
    return TextSearch.matches(of: expression, in: text).map { (text as NSString).substring(with: $0) }
}

@Suite struct TextSearchTests {
    @Test func searchOfEveryNoteStopsAtTheLineCap() {
        var memo = SearchMemo(query: "", options: SearchOptions())
        let crowded = (0..<60).map { note($0, matches: 60) }
        let capped = TextSearch.searchAll(crowded, query: "hit", options: SearchOptions(), memo: &memo) ?? []
        #expect(capped.count == 40, "search of every note stops once 2,000 lines are listed")
        #expect(capped.allSatisfy { $0.lines.count == 50 && $0.isClipped }, "each note lists at most 50 lines and says it has more")
    }

    @Test func totalBudgetCutsTheLastListedNote() {
        let notes = (0..<70).map { note($0, matches: 30) }
        var budgetMemo = SearchMemo(query: "", options: SearchOptions())
        let budgeted = TextSearch.searchAll(notes, query: "hit", options: SearchOptions(), memo: &budgetMemo) ?? []
        #expect(budgeted.count == 67, "the last listed note is the one the total budget runs out in")
        #expect(budgeted.reduce(0) { $0 + $1.lines.count } == 2_000, "lines in all stop at the budget")
        #expect(budgeted.last?.lines.count == 20 && budgeted.last?.isClipped == true, "the note cut short by the budget is marked as clipped")
        #expect(budgeted.first?.isClipped == false, "a note listed in full is not marked as clipped")
    }

    @Test func unchangedNotesReuseTheirLines() {
        var reuse = SearchMemo(query: "", options: SearchOptions())
        let first = [note(1, matches: 2), note(2, matches: 1)]
        _ = TextSearch.searchAll(first, query: "hit", options: SearchOptions(), memo: &reuse)
        let sameRevision = [note(1, matches: 5), note(2, matches: 1)]
        #expect(TextSearch.searchAll(sameRevision, query: "hit", options: SearchOptions(), memo: &reuse)?.first?.lines.count == 2, "a note whose revision has not moved reuses its lines")
        let newRevision = [note(1, matches: 5, revision: 2), note(2, matches: 1)]
        #expect(TextSearch.searchAll(newRevision, query: "hit", options: SearchOptions(), memo: &reuse)?.first?.lines.count == 5, "a note with a new revision is searched again")
        #expect(TextSearch.searchAll([note(1, matches: 3, revision: 2)], query: "line", options: SearchOptions(), memo: &reuse)?.first?.lines.count == 3, "a new query searches every note again")
        #expect(TextSearch.searchAll(first, query: "", options: SearchOptions(), memo: &reuse)?.count == 0, "an empty query finds nothing")
        #expect(TextSearch.searchAll(first, query: "(", options: SearchOptions(regex: true), memo: &reuse) == nil, "a broken regular expression searches nothing")
    }

    @Test func cancelledSearchReturnsEarly() async {
        let crowded = (0..<60).map { note($0, matches: 60) }
        let cancelled = await Task.detached { () -> [NoteMatches]? in
            withUnsafeCurrentTask { $0?.cancel() }
            var memo = SearchMemo(query: "", options: SearchOptions())
            return TextSearch.searchAll(crowded, query: "hit", options: SearchOptions(), memo: &memo)
        }.value
        #expect(cancelled == nil, "a cancelled search of every note returns early")
    }

    @Test func regexSearchSkipsLongLinesButPlainSearchReadsThem() {
        let long = "short x\n" + String(repeating: "x", count: TextSearch.longLineLimit + 1) + "\nlast x"
        let regex = try! TextSearch.expression(for: "x+", options: SearchOptions(regex: true))!
        let skipped = TextSearch.matches(of: regex, in: long, skippingLongLines: true)
        #expect(skipped.count == 2, "regex search skips lines longer than the limit")
        #expect(skipped.last.map { (long as NSString).substring(with: $0) } == "x", "matches after a skipped line keep their place")
        #expect(TextSearch.matches(of: regex, in: long).count == 3, "searches that do not skip still read long lines")
        #expect(TextSearch.ranges(of: "x", options: SearchOptions(regex: true), in: long)?.count == 2, "find in regex mode skips long lines")
        #expect(TextSearch.ranges(of: "x", options: SearchOptions(), in: "x\n" + String(repeating: "y", count: TextSearch.longLineLimit) + "x")?.count == 2, "plain find reads long lines")
        #expect(TextSearch.ranges(of: "(", options: SearchOptions(regex: true), in: "(") == nil, "find reports a broken regular expression")
        #expect(TextSearch.ranges(of: "", options: SearchOptions(), in: "abc") == [], "find with no query finds nothing")
    }

    @Test func nextAndFirstMatchWrapAround() {
        let ranges = [NSRange(location: 2, length: 1), NSRange(location: 6, length: 1), NSRange(location: 9, length: 1)]
        #expect(TextSearch.nextMatch(in: ranges, from: NSRange(location: 2, length: 1), forward: true) == ranges[1], "next match is after the selected one")
        #expect(TextSearch.nextMatch(in: ranges, from: NSRange(location: 6, length: 0), forward: true) == ranges[1], "next match from a caret on a match is that match")
        #expect(TextSearch.nextMatch(in: ranges, from: NSRange(location: 9, length: 1), forward: true) == ranges[0], "next match wraps to the first")
        #expect(TextSearch.nextMatch(in: ranges, from: NSRange(location: 6, length: 1), forward: false) == ranges[0], "previous match is before the selection")
        #expect(TextSearch.nextMatch(in: ranges, from: NSRange(location: 2, length: 1), forward: false) == ranges[2], "previous match wraps to the last")
        #expect(TextSearch.nextMatch(in: [], from: NSRange(location: 0, length: 0), forward: true) == nil, "no matches, nowhere to go")
        #expect(TextSearch.firstMatch(in: ranges, atOrAfter: 6) == ranges[1], "first match at the caret")
        #expect(TextSearch.firstMatch(in: ranges, atOrAfter: 7) == ranges[2], "first match after the caret")
        #expect(TextSearch.firstMatch(in: ranges, atOrAfter: 10) == ranges[0], "first match wraps past the end")
    }

    @Test @MainActor func plainSearchOptions() {
        #expect(ranges("note", "Note note NOTE") == ["Note", "note", "NOTE"], "search ignores case by default")
        #expect(ranges("note", "Note note", SearchOptions(caseSensitive: true)) == ["note"], "case-sensitive search")
        #expect(ranges("cat", "cat concat cat_ (cat)", SearchOptions(wholeWord: true)) == ["cat", "cat"], "whole word skips parts of words")
        #expect(ranges("c++", "c++ and c++x", SearchOptions(wholeWord: true)) == ["c++"], "whole word works next to punctuation")
        #expect(ranges("café", "Café time, cafés", SearchOptions(wholeWord: true)) == ["Café"], "whole word understands accented letters")
        #expect(ranges("a.c", "abc a.c") == ["a.c"], "plain search treats symbols literally")
    }

    @Test @MainActor func regexSearch() {
        #expect(ranges("a.c", "abc a.c", SearchOptions(regex: true)) == ["abc", "a.c"], "regex search")
        #expect(ranges("^- ", "- one\n- two\nx - three", SearchOptions(regex: true)) == ["- ", "- "], "regex anchors match each line")
        #expect(ranges("x*", "aaa", SearchOptions(regex: true)) == [], "empty regex matches are skipped")
        #expect(ranges("(", "(", SearchOptions(regex: true)) == ["<invalid>"], "bad regex is reported")
        #expect((try? TextSearch.expression(for: "", options: SearchOptions())) == .some(nil), "empty query searches nothing")
    }

    @Test @MainActor func lineMatchesCarryLineNumbersAndSnippets() {
        let text = "intro\r\n  find me here\n\nlast find"
        let expression = try! TextSearch.expression(for: "find", options: SearchOptions())!
        let lines = TextSearch.lineMatches(of: expression, in: text, limit: 10)
        #expect(lines.map(\.line) == [2, 4], "line numbers count every kind of line break")
        #expect(lines.first.map { [$0.before, $0.matched, $0.after] } == ["", "find", " me here"], "line snippet splits around the match")
        #expect(lines.last.map { [$0.before, $0.after] } == ["last ", ""], "line snippet at the end of the text")
        #expect(TextSearch.lineMatches(of: expression, in: text, limit: 1).count == 1, "line matches respect the limit")
    }

    @Test @MainActor func regexReplaceUsesCaptureGroups() {
        let regex = try! TextSearch.expression(for: "(\\w+)@(\\w+)", options: SearchOptions(regex: true))!
        let mail = "mail a@b now"
        let range = TextSearch.matches(of: regex, in: mail)[0]
        #expect(TextSearch.replacement(for: range, in: mail, expression: regex, template: "$2 at $1", options: SearchOptions(regex: true)) == "b at a", "regex replace uses groups")
    }

    @Test @MainActor func plainReplaceInsertsTextAsTypedAndReplaceAllCounts() {
        let literal = try! TextSearch.expression(for: "cost", options: SearchOptions())!
        let price = "cost: cost"
        #expect(TextSearch.replacement(for: TextSearch.matches(of: literal, in: price)[1], in: price, expression: literal, template: "$5", options: SearchOptions()) == "$5", "plain replace inserts text as typed")
        #expect(TextSearch.replacement(for: NSRange(location: 1, length: 3), in: price, expression: literal, template: "x", options: SearchOptions()) == nil, "stale range is not replaced")
        let all = TextSearch.replacingAll(in: "a-b-c", expression: try! TextSearch.expression(for: "-", options: SearchOptions())!, template: "+", options: SearchOptions())
        #expect(all.text == "a+b+c" && all.count == 2, "replace all")
    }

    @Test @MainActor func wholeWordReplaceSeesTheTextAroundTheMatch() {
        let word = try! TextSearch.expression(for: "cat", options: SearchOptions(wholeWord: true))!
        let pets = "concat cat"
        #expect(TextSearch.replacement(for: NSRange(location: 7, length: 3), in: pets, expression: word, template: "dog", options: SearchOptions(wholeWord: true)) == "dog", "single replace sees the text around the match")
    }
}
