import Foundation
import HardydoNotesCore

func runFuzzyMatchChecks() {
    check(FuzzyMatch.score("gro", in: "Groceries") != nil, "a prefix matches")
    check(FuzzyMatch.score("gcs", in: "Groceries") != nil, "letters in order match")
    check(FuzzyMatch.score("xyz", in: "Groceries") == nil, "missing letters do not match")
    checkEqual(FuzzyMatch.rank(["Reading list", "Meeting notes", "Notes"], query: "notes") { $0 }, ["Notes", "Meeting notes"], "the closest title ranks first")
    checkEqual(FuzzyMatch.rank(["Reading list", "Meeting notes", "Notes"], query: "  ") { $0 }, ["Reading list", "Meeting notes", "Notes"], "an empty query keeps every candidate in order")
    let prepared = FuzzyMatch.Query("Gro Ce")
    check(["Groceries", "grocery cellar", "Garden"].map(prepared.score) == ["Groceries", "grocery cellar", "Garden"].map { FuzzyMatch.score("Gro Ce", in: $0) }, "a prepared query scores as the one-off score does")

    let notes = (0..<5).map { Note(body: "Note \($0)") }
    var groups = NoteGroups()
    let group = groups.create(name: "Folded", with: notes[1].id)
    groups.add(notes[3].id, to: group)
    groups.update(group) { $0.isCollapsed = true }
    let listed = groups.orderedNotes(notes).map(\.summary)
    let candidates = QuickOpenRanking.candidates(openTabs: [notes[4].id, notes[1].id], listed: listed)
    checkEqual(candidates.map(\.title), ["Note 4", "Note 1", "Note 0", "Note 3", "Note 2"], "open tabs come first, then the rest in sidebar order, folded groups included")
    checkEqual(Set(candidates.map(\.id)).count, candidates.count, "each note is offered once")
    checkEqual(QuickOpenRanking.candidates(openTabs: [UUID()], listed: listed).count, listed.count, "a tab of a note that is gone is skipped")
}
