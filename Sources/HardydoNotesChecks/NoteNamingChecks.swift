import Foundation
import HardydoNotesCore

func runNamingChecks() {
    checkEqual(NoteNaming.title(for: "# Shopping list\n- milk"), "Shopping list", "title strips heading")
    checkEqual(NoteNaming.title(for: "\n\n   \nHello"), "Hello", "title skips blank lines")
    checkEqual(NoteNaming.title(for: ""), NoteNaming.untitled, "empty title")
    checkEqual(NoteNaming.fileName(for: "a/b: c?"), "a-b- c-.md", "file name replaces forbidden characters")
    checkEqual(NoteNaming.fileName(for: "..."), NoteNaming.untitled + ".md", "file name never empty")
    checkEqual(Note(body: "Title\n\nfirst line\nsecond").snippet, "first line", "snippet is second non-empty line")
    checkEqual(Note(body: "Title\n## Section").snippet, "Section", "snippet hides heading marks")
    checkEqual(NoteNaming.title(for: "{\n  \"name\": \"demo\"\n}"), "\"name\": \"demo\"", "a JSON note is titled by its first line with words")
    checkEqual(Note(body: "{\n  \"name\": \"demo\",\n  \"port\": 80\n}").snippet, "\"port\": 80", "snippet follows the title line")
    checkEqual(NoteNaming.title(for: "---\n***"), NoteNaming.untitled, "lines of only symbols are no title")
    checkEqual(Note(body: "#!/bin/bash\nls", localFile: LocalFile(path: "/tmp/run.sh")).snippet, "#!/bin/bash", "a shebang keeps its hash in the snippet")
}

func runNoteSummaryChecks() {
    let file = LocalFile(path: "/tmp/a.md")
    let note = Note(body: "# Title\nsnippet\nmore", isLocked: true, localFile: file, isPinned: true)
    let summary = note.summary
    checkEqual(summary.title, "a.md", "an opened file is listed by its name")
    checkEqual(summary.snippet, "Title", "an opened file shows its first line")
    check(summary.isPinned && summary.isLocked && summary.filePath == file.path, "the summary keeps pin, lock and path")
    var longer = note
    longer.body += "\nanother line far below"
    checkEqual(longer.summary.title, summary.title, "text below the first lines leaves the title alone")
    check(longer.summary.snippet == summary.snippet && longer.summary.id == summary.id, "text below the first lines leaves the row's text alone")
}

func runSummaryChecks() {
    var note = Note(body: "{\n# Plan\n\n#todo buy milk")
    checkEqual(note.title, "Plan", "title skips punctuation-only lines")
    checkEqual(note.snippet, "#todo buy milk", "a hashtag stays in the snippet")
    note.body = "# New"
    check(note.title == "New" && note.snippet.isEmpty, "the title follows body edits")
}
