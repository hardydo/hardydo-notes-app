import Foundation
import HardydoNotesCore
import Testing

@Suite struct FuzzyMatchTests {
    @Test func scoreMatchesLettersInOrder() {
        #expect(FuzzyMatch.score("gro", in: "Groceries") != nil, "a prefix matches")
        #expect(FuzzyMatch.score("gcs", in: "Groceries") != nil, "letters in order match")
        #expect(FuzzyMatch.score("xyz", in: "Groceries") == nil, "missing letters do not match")
    }

    @Test func rankPutsTheClosestTitleFirst() {
        #expect(FuzzyMatch.rank(["Reading list", "Meeting notes", "Notes"], query: "notes") { $0 } == ["Notes", "Meeting notes"], "the closest title ranks first")
        #expect(FuzzyMatch.rank(["Reading list", "Meeting notes", "Notes"], query: "  ") { $0 } == ["Reading list", "Meeting notes", "Notes"], "an empty query keeps every candidate in order")
    }

    @Test func preparedQueryScoresLikeTheOneOffScore() {
        let prepared = FuzzyMatch.Query("Gro Ce")
        #expect(["Groceries", "grocery cellar", "Garden"].map(prepared.score) == ["Groceries", "grocery cellar", "Garden"].map { FuzzyMatch.score("Gro Ce", in: $0) }, "a prepared query scores as the one-off score does")
    }

    @Test func quickOpenListsOpenTabsFirstThenSidebarOrder() {
        let notes = (0..<5).map { Note(body: "Note \($0)") }
        var groups = NoteGroups()
        let group = groups.create(name: "Folded", with: notes[1].id)
        groups.add(notes[3].id, to: group)
        groups.update(group) { $0.isCollapsed = true }
        let listed = groups.orderedNotes(notes).map(\.summary)
        let candidates = QuickOpenRanking.candidates(openTabs: [notes[4].id, notes[1].id], listed: listed)
        #expect(candidates.map(\.title) == ["Note 4", "Note 1", "Note 0", "Note 3", "Note 2"], "open tabs come first, then the rest in sidebar order, folded groups included")
        #expect(Set(candidates.map(\.id)).count == candidates.count, "each note is offered once")
        #expect(QuickOpenRanking.candidates(openTabs: [UUID()], listed: listed).count == listed.count, "a tab of a note that is gone is skipped")
    }
}
