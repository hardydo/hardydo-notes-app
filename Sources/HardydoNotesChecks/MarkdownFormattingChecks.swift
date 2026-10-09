import Foundation
import HardydoNotesCore

private func apply(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

func runFormattingChecks() {
    var text = "hello world"
    var edit = MarkdownFormatting.toggleWrap(text, selection: NSRange(location: 6, length: 5), marker: "**")
    text = apply(edit, to: text)
    checkEqual(text, "hello **world**", "wrap bold")
    checkEqual(edit.selection, NSRange(location: 8, length: 5), "selection stays on word")

    edit = MarkdownFormatting.toggleWrap(text, selection: edit.selection, marker: "**")
    checkEqual(apply(edit, to: text), "hello world", "unwrap bold around selection")

    edit = MarkdownFormatting.toggleWrap("x **y** z", selection: NSRange(location: 2, length: 5), marker: "**")
    checkEqual(apply(edit, to: "x **y** z"), "x y z", "unwrap bold inside selection")

    edit = MarkdownFormatting.toggleWrap("a **bold** b", selection: NSRange(location: 4, length: 4), marker: "*")
    checkEqual(apply(edit, to: "a **bold** b"), "a ***bold*** b", "italic on bold word adds italic")
    edit = MarkdownFormatting.toggleWrap("***x***", selection: NSRange(location: 3, length: 1), marker: "*")
    checkEqual(apply(edit, to: "***x***"), "**x**", "italic removed from bold italic")
    edit = MarkdownFormatting.toggleWrap("**bold**", selection: NSRange(location: 0, length: 8), marker: "*")
    checkEqual(apply(edit, to: "**bold**"), "***bold***", "italic on selected bold text keeps bold")

    edit = MarkdownFormatting.toggleWrap("ab", selection: NSRange(location: 1, length: 0), marker: "*")
    checkEqual(apply(edit, to: "ab"), "a**b", "empty selection inserts markers")
    checkEqual(edit.selection, NSRange(location: 2, length: 0), "caret between markers")

    text = "one\ntwo\n\nthree"
    edit = MarkdownFormatting.toggleLinePrefix(text, selection: NSRange(location: 0, length: (text as NSString).length), prefix: .numbered)
    text = apply(edit, to: text)
    checkEqual(text, "1. one\n2. two\n\n3. three", "number lines skipping blanks")
    edit = MarkdownFormatting.toggleLinePrefix(text, selection: NSRange(location: 0, length: (text as NSString).length), prefix: .numbered)
    checkEqual(apply(edit, to: text), "one\ntwo\n\nthree", "toggle numbered off")

    edit = MarkdownFormatting.toggleLinePrefix("# Title", selection: NSRange(location: 3, length: 0), prefix: .heading(2))
    checkEqual(apply(edit, to: "# Title"), "## Title", "switch heading level")
    checkEqual(edit.selection, NSRange(location: 4, length: 0), "caret follows heading change")

    edit = MarkdownFormatting.toggleLinePrefix("- item\nnext", selection: NSRange(location: 2, length: 0), prefix: .task)
    checkEqual(apply(edit, to: "- item\nnext"), "- [ ] item\nnext", "bullet becomes task, only current line")

    edit = MarkdownFormatting.toggleLinePrefix("", selection: NSRange(location: 0, length: 0), prefix: .quote)
    checkEqual(apply(edit, to: ""), "> ", "quote on empty document")

    edit = MarkdownFormatting.insertLink("see docs", selection: NSRange(location: 4, length: 4))
    checkEqual(apply(edit, to: "see docs"), "see [docs](https://)", "insert link")
    checkEqual(edit.selection, NSRange(location: 11, length: 8), "url selected after link insert")

    let cell = MarkdownFormatting.tableFirstCell
    edit = MarkdownFormatting.insertBlock("Intro", selection: NSRange(location: 2, length: 0), block: MarkdownFormatting.table(rows: 1, columns: 2), select: cell)
    text = apply(edit, to: "Intro")
    checkEqual(text, "Intro\n\n" + MarkdownFormatting.table(rows: 1, columns: 2) + "\n", "table goes below the line with a blank line before it")
    checkEqual(MarkdownFormatting.table(rows: 1, columns: 2), "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |", "a 1×2 table")
    checkEqual(MarkdownFormatting.table(rows: 3, columns: 1), "| Column 1 |\n| --- |\n|  |\n|  |\n|  |", "rows and columns follow the request")
    checkEqual(MarkdownFormatting.table(rows: 0, columns: 0), "| Column 1 |\n| --- |", "at least one column, no body rows")
    checkEqual((text as NSString).substring(with: edit.selection), "Column 1", "first header cell is selected")
    edit = MarkdownFormatting.insertBlock("a\nb", selection: NSRange(location: 0, length: 0), block: MarkdownFormatting.rule)
    checkEqual(apply(edit, to: "a\nb"), "a\n\n---\n\nb", "a rule never turns the line above into a heading")
    edit = MarkdownFormatting.insertBlock("a\n\n", selection: NSRange(location: 2, length: 0), block: MarkdownFormatting.rule)
    checkEqual(apply(edit, to: "a\n\n"), "a\n\n---\n", "on a blank line the block fills it")
    checkEqual(edit.selection, NSRange(location: 7, length: 0), "caret lands on the line after the block")
    edit = MarkdownFormatting.insertBlock("", selection: NSRange(location: 0, length: 0), block: MarkdownFormatting.rule)
    checkEqual(apply(edit, to: ""), "---\n", "block in an empty note")
}
