import HardydoNotesCore
import Foundation

func runTabPinChecks() {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    var tabs = TabList(ids: [a, b, c], active: a)
    tabs.pin(c)
    checkEqual(tabs.ids, [c, a, b], "a pinned tab moves to the front")
    check(tabs.isPinned(c) && !tabs.isPinned(a), "only the pinned tab reports pinned")
    tabs.open(d, keep: true)
    tabs.activate(c)
    tabs.open(UUID(), keep: true)
    check(tabs.ids.firstIndex(of: c) == 0 && tabs.pinnedCount == 1, "new tabs never open among pinned ones")

    tabs = TabList(ids: [a, b, c], active: b, pinned: [b])
    checkEqual(tabs.ids, [b, a, c], "restored pins come first")
    tabs.closeAll()
    checkEqual(tabs.ids, [b], "close all keeps pinned tabs")
    tabs = TabList(ids: [a, b, c, d], active: c, pinned: [a])
    tabs.closeOthers(c)
    checkEqual(tabs.ids, [a, c], "close others keeps pinned tabs")
    tabs = TabList(ids: [a, b, c], active: c, pinned: [a, b])
    tabs.closeRight(of: a)
    checkEqual(tabs.ids, [a, b], "close to the right keeps pinned tabs")
    check(!tabs.canCloseAll && !tabs.canCloseOthers(a) && !tabs.canCloseRight(of: a),
          "close commands are off when only pinned tabs are left")
    tabs.open(c, keep: true)
    check(tabs.canCloseOthers(a) && tabs.canCloseRight(of: a) && !tabs.canCloseRight(of: c),
          "close commands turn on while an unpinned tab can close")
    tabs.close(c)
    tabs.reorder([b, a])
    checkEqual(tabs.ids, [b, a], "pinned tabs reorder among themselves")
    tabs.unpin(b)
    check(tabs.ids == [a, b] && !tabs.isPinned(b), "an unpinned tab goes right after the pinned ones")

    tabs = TabList(ids: [a, b, c], active: a, pinned: [a])
    tabs.reorder([b, a, c])
    checkEqual(tabs.ids, [a, b, c], "a drag never moves a tab across the pinned boundary")
    tabs.reorder([a, b])
    checkEqual(tabs.ids, [a, b, c], "an order missing a tab is ignored")
    tabs.reorder([a, c, b])
    checkEqual(tabs.ids, [a, c, b], "unpinned tabs reorder after the pinned ones")

    tabs = TabList(ids: [a, b, c], active: b)
    tabs.close(b)
    tabs.close(c)
    checkEqual(tabs.reopen(existing: [a, b, c]), c, "reopen brings back the last closed tab")
    checkEqual(tabs.reopen(existing: [a, c]), nil, "a deleted note is not reopened")
    tabs = TabList(ids: [a, b], active: a, pinned: [a])
    tabs.close(a)
    tabs.reopen(existing: [a, b])
    check(tabs.isPinned(a) && tabs.ids == [a, b], "a reopened pinned tab is pinned again")
    tabs.activate(at: 1)
    checkEqual(tabs.active, b, "activate by position")
}

func runLineEditingChecks() {
    func apply(_ text: String, _ edit: TextEdit?) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
    let text = "one\ntwo\nthree"
    let down = LineEditing.moveLines(text, selection: NSRange(location: 1, length: 0), .down)
    checkEqual(apply(text, down), "two\none\nthree", "move line down")
    checkEqual(down?.selection.location, 5, "the caret follows a moved line")
    checkEqual(apply(text, LineEditing.moveLines(text, selection: NSRange(location: 9, length: 0), .up)), "one\nthree\ntwo", "move the last line up")
    check(LineEditing.moveLines(text, selection: NSRange(location: 0, length: 0), .up) == nil, "the first line cannot move up")
    checkEqual(apply(text, LineEditing.copyLines(text, selection: NSRange(location: 5, length: 0), .down)), "one\ntwo\ntwo\nthree", "copy line down")
    checkEqual(apply(text, LineEditing.copyLines(text, selection: NSRange(location: 9, length: 0), .down)), "one\ntwo\nthree\nthree", "copy the last line down")
    checkEqual(apply(text, LineEditing.deleteLines(text, selection: NSRange(location: 5, length: 0))), "one\nthree", "delete line")
    checkEqual(apply(text, LineEditing.deleteLines(text, selection: NSRange(location: 9, length: 0))), "one\ntwo", "delete the last line")
    let indented = "  item"
    let below = LineEditing.insertLine(indented, selection: NSRange(location: 3, length: 0), .down)
    checkEqual(apply(indented, below), "  item\n  ", "insert line below keeps indentation")
    checkEqual(apply(indented, LineEditing.insertLine(indented, selection: NSRange(location: 3, length: 0), .up)), "  \n  item", "insert line above")
    checkEqual(apply(text, LineEditing.indent(text, selection: NSRange(location: 0, length: 6), unit: "    ")), "    one\n    two\nthree", "indent selected lines")
    checkEqual(apply("    one\n  two", LineEditing.outdent("    one\n  two", selection: NSRange(location: 0, length: 13), unit: "    ")), "one\ntwo", "outdent removes up to one unit")
    checkEqual(LineEditing.indentUnit(for: "a\n\tb"), "\t", "tab indented text indents with tabs")
    let code = "let a = 1\n  let b = 2"
    let commented = apply(code, LineEditing.toggleComment(code, selection: NSRange(location: 0, length: 12), language: .swift))
    checkEqual(commented, "// let a = 1\n//   let b = 2", "comment lines at their shared indentation")
    checkEqual(apply(commented, LineEditing.toggleComment(commented, selection: NSRange(location: 0, length: 14), language: .swift)), code, "uncomment restores the lines")
    checkEqual(apply("# Title", LineEditing.toggleComment("# Title", selection: NSRange(location: 0, length: 0), language: .markdown)), "<!-- # Title -->", "markdown comments are HTML comments")
    checkEqual(LineEditing.selectLine(text, selection: NSRange(location: 1, length: 0)), NSRange(location: 0, length: 4), "select line")
    checkEqual(LineEditing.selectLine(text, selection: NSRange(location: 0, length: 4)), NSRange(location: 0, length: 8), "select line again adds the next line")
    checkEqual(LineEditing.location(ofLine: 3, in: text), 8, "go to line")
    checkEqual(LineEditing.location(ofLine: 99, in: text), 8, "go to a line past the end lands on the last line")
}

func runSummaryChecks() {
    var note = Note(body: "{\n# Plan\n\n#todo buy milk")
    checkEqual(note.title, "Plan", "title skips punctuation-only lines")
    checkEqual(note.snippet, "#todo buy milk", "a hashtag stays in the snippet")
    note.body = "# New"
    check(note.title == "New" && note.snippet.isEmpty, "the title follows body edits")
}

func runFuzzyMatchChecks() {
    check(FuzzyMatch.score("gro", in: "Groceries") != nil, "a prefix matches")
    check(FuzzyMatch.score("gcs", in: "Groceries") != nil, "letters in order match")
    check(FuzzyMatch.score("xyz", in: "Groceries") == nil, "missing letters do not match")
    checkEqual(FuzzyMatch.rank(["Reading list", "Meeting notes", "Notes"], query: "notes") { $0 }, ["Notes", "Meeting notes"], "the closest title ranks first")
}
