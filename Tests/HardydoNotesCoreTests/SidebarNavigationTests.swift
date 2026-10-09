import Foundation
import HardydoNotesCore
import Testing

private struct Navigation {
    let notes = (0..<5).map { Note(body: "n\($0)") }
    let files = [Note(body: "f0")]
    var groups = NoteGroups()
    let work: UUID

    init() {
        work = groups.create(name: "Work", with: notes[1].id)
        groups.add(notes[2].id, to: work)
    }

    mutating func collapseWork() {
        groups.update(work) { $0.isCollapsed = true }
    }

    func step(_ from: Note?, _ offset: Int, _ list: [Note]? = nil, _ fileList: [Note]? = nil) -> String? {
        let list = list ?? notes, fileList = fileList ?? files
        return groups.step(from: from?.id, by: offset, appNotes: list, fileNotes: fileList).flatMap { id in (list + fileList).first { $0.id == id }?.body }
    }
}

@Suite struct SidebarNavigationTests {
    @Test func stepsMoveBetweenShownNotesAndOpenedFiles() {
        let navigation = Navigation()
        let notes = navigation.notes, files = navigation.files
        #expect(navigation.step(notes[0], 1) == "n1", "↓ moves to the next shown note")
        #expect(navigation.step(notes[3], -1) == "n2", "↑ moves to the previous shown note")
        #expect(navigation.step(notes[4], 1) == "f0", "↓ from the last note continues into the opened files")
        #expect(navigation.step(files[0], 1) == "f0", "↓ on the last row stays there")
        #expect(navigation.step(notes[0], -1) == "n0", "↑ on the first row stays there")
        #expect(navigation.step(nil, 1) == "n0", "with nothing open, a step lands on the first note")
    }

    @Test func collapsedGroupsAreSkippedBySteps() {
        var navigation = Navigation()
        navigation.collapseWork()
        let notes = navigation.notes
        #expect(navigation.step(notes[2], 1) == "n3", "↓ from a note in a collapsed group lands on the next shown note")
        #expect(navigation.step(notes[1], -1) == "n0", "↑ from a note in a collapsed group lands on the previous shown note")
        #expect(navigation.step(notes[0], 1) == "n3", "↓ skips the notes of a collapsed group")
    }

    @Test func collapsedNoteWithNothingShownBeforeItLandsOnTheFirstShownNote() {
        var navigation = Navigation()
        navigation.collapseWork()
        let notes = navigation.notes, files = navigation.files
        var hidden = NoteGroups()
        let all = hidden.create(name: "All", with: notes[0].id)
        hidden.update(all) { $0.isCollapsed = true }
        #expect(hidden.step(from: notes[0].id, by: -1, appNotes: [notes[0]], fileNotes: files).flatMap { $0 == files[0].id ? "f0" : nil } == "f0",
                "↑ from a collapsed note with nothing shown before it lands on the first shown note")
        #expect(navigation.step(notes[0], 1, [], []) == nil, "an empty list has nowhere to step")
    }
}
