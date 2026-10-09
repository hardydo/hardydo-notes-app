import Foundation
import HardydoNotesCore
import Testing

@Suite struct NoteNamingTests {
    @Test func titleStripsHeadingMarksAndSkipsBlankLines() {
        #expect(NoteNaming.title(for: "# Shopping list\n- milk") == "Shopping list", "title strips heading")
        #expect(NoteNaming.title(for: "\n\n   \nHello") == "Hello", "title skips blank lines")
        #expect(NoteNaming.title(for: "") == NoteNaming.untitled, "empty title")
    }

    @Test func fileNamesReplaceForbiddenCharactersAndAreNeverEmpty() {
        #expect(NoteNaming.fileName(for: "a/b: c?") == "a-b- c-.md", "file name replaces forbidden characters")
        #expect(NoteNaming.fileName(for: "...") == NoteNaming.untitled + ".md", "file name never empty")
    }

    @Test func snippetIsTheSecondNonEmptyLineWithoutHeadingMarks() {
        #expect(Note(body: "Title\n\nfirst line\nsecond").snippet == "first line", "snippet is second non-empty line")
        #expect(Note(body: "Title\n## Section").snippet == "Section", "snippet hides heading marks")
    }

    @Test func jsonNoteIsTitledByItsFirstLineWithWords() {
        #expect(NoteNaming.title(for: "{\n  \"name\": \"demo\"\n}") == "\"name\": \"demo\"", "a JSON note is titled by its first line with words")
        #expect(Note(body: "{\n  \"name\": \"demo\",\n  \"port\": 80\n}").snippet == "\"port\": 80", "snippet follows the title line")
    }

    @Test func linesOfOnlySymbolsAreNoTitle() {
        #expect(NoteNaming.title(for: "---\n***") == NoteNaming.untitled, "lines of only symbols are no title")
    }

    @Test func shebangKeepsItsHashInTheSnippet() {
        #expect(Note(body: "#!/bin/bash\nls", localFile: LocalFile(path: "/tmp/run.sh")).snippet == "#!/bin/bash", "a shebang keeps its hash in the snippet")
    }

    @Test func openedFileIsListedByItsNameAndKeepsPinLockAndPath() {
        let file = LocalFile(path: "/tmp/a.md")
        let note = Note(body: "# Title\nsnippet\nmore", isLocked: true, localFile: file, isPinned: true)
        let summary = note.summary
        #expect(summary.title == "a.md", "an opened file is listed by its name")
        #expect(summary.snippet == "Title", "an opened file shows its first line")
        #expect(summary.isPinned && summary.isLocked && summary.filePath == file.path, "the summary keeps pin, lock and path")
    }

    @Test func textBelowTheFirstLinesLeavesTheRowAlone() {
        let note = Note(body: "# Title\nsnippet\nmore", isLocked: true, localFile: LocalFile(path: "/tmp/a.md"), isPinned: true)
        let summary = note.summary
        var longer = note
        longer.body += "\nanother line far below"
        #expect(longer.summary.title == summary.title, "text below the first lines leaves the title alone")
        #expect(longer.summary.snippet == summary.snippet && longer.summary.id == summary.id, "text below the first lines leaves the row's text alone")
    }

    @Test func titleSkipsPunctuationOnlyLinesAndFollowsBodyEdits() {
        var note = Note(body: "{\n# Plan\n\n#todo buy milk")
        #expect(note.title == "Plan", "title skips punctuation-only lines")
        #expect(note.snippet == "#todo buy milk", "a hashtag stays in the snippet")
        note.body = "# New"
        #expect(note.title == "New" && note.snippet.isEmpty, "the title follows body edits")
    }
}
