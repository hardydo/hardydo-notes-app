import Foundation
import HardydoNotesCore
import Testing

private func apply(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

@Suite struct MarkdownFormattingTests {
    @Test func boldWrapsAndUnwraps() {
        var text = "hello world"
        var edit = MarkdownFormatting.toggleWrap(text, selection: NSRange(location: 6, length: 5), marker: "**")
        text = apply(edit, to: text)
        #expect(text == "hello **world**", "wrap bold")
        #expect(edit.selection == NSRange(location: 8, length: 5), "selection stays on word")

        edit = MarkdownFormatting.toggleWrap(text, selection: edit.selection, marker: "**")
        #expect(apply(edit, to: text) == "hello world", "unwrap bold around selection")

        edit = MarkdownFormatting.toggleWrap("x **y** z", selection: NSRange(location: 2, length: 5), marker: "**")
        #expect(apply(edit, to: "x **y** z") == "x y z", "unwrap bold inside selection")
    }

    @Test func italicOnBoldTextAddsOrRemovesItalic() {
        var edit = MarkdownFormatting.toggleWrap("a **bold** b", selection: NSRange(location: 4, length: 4), marker: "*")
        #expect(apply(edit, to: "a **bold** b") == "a ***bold*** b", "italic on bold word adds italic")
        edit = MarkdownFormatting.toggleWrap("***x***", selection: NSRange(location: 3, length: 1), marker: "*")
        #expect(apply(edit, to: "***x***") == "**x**", "italic removed from bold italic")
        edit = MarkdownFormatting.toggleWrap("**bold**", selection: NSRange(location: 0, length: 8), marker: "*")
        #expect(apply(edit, to: "**bold**") == "***bold***", "italic on selected bold text keeps bold")
    }

    @Test func emptySelectionInsertsMarkers() {
        let edit = MarkdownFormatting.toggleWrap("ab", selection: NSRange(location: 1, length: 0), marker: "*")
        #expect(apply(edit, to: "ab") == "a**b", "empty selection inserts markers")
        #expect(edit.selection == NSRange(location: 2, length: 0), "caret between markers")
    }

    @Test func numberedListSkipsBlankLinesAndTogglesOff() {
        var text = "one\ntwo\n\nthree"
        var edit = MarkdownFormatting.toggleLinePrefix(text, selection: NSRange(location: 0, length: (text as NSString).length), prefix: .numbered)
        text = apply(edit, to: text)
        #expect(text == "1. one\n2. two\n\n3. three", "number lines skipping blanks")
        edit = MarkdownFormatting.toggleLinePrefix(text, selection: NSRange(location: 0, length: (text as NSString).length), prefix: .numbered)
        #expect(apply(edit, to: text) == "one\ntwo\n\nthree", "toggle numbered off")
    }

    @Test func headingLevelSwitches() {
        let edit = MarkdownFormatting.toggleLinePrefix("# Title", selection: NSRange(location: 3, length: 0), prefix: .heading(2))
        #expect(apply(edit, to: "# Title") == "## Title", "switch heading level")
        #expect(edit.selection == NSRange(location: 4, length: 0), "caret follows heading change")
    }

    @Test func bulletBecomesTaskOnTheCurrentLineOnly() {
        let edit = MarkdownFormatting.toggleLinePrefix("- item\nnext", selection: NSRange(location: 2, length: 0), prefix: .task)
        #expect(apply(edit, to: "- item\nnext") == "- [ ] item\nnext", "bullet becomes task, only current line")
    }

    @Test func quoteOnAnEmptyDocument() {
        let edit = MarkdownFormatting.toggleLinePrefix("", selection: NSRange(location: 0, length: 0), prefix: .quote)
        #expect(apply(edit, to: "") == "> ", "quote on empty document")
    }

    @Test func insertLinkSelectsTheUrl() {
        let edit = MarkdownFormatting.insertLink("see docs", selection: NSRange(location: 4, length: 4))
        #expect(apply(edit, to: "see docs") == "see [docs](https://)", "insert link")
        #expect(edit.selection == NSRange(location: 11, length: 8), "url selected after link insert")
    }

    @Test func tableGoesBelowTheLineWithTheRequestedSize() {
        let cell = MarkdownFormatting.tableFirstCell
        let edit = MarkdownFormatting.insertBlock("Intro", selection: NSRange(location: 2, length: 0), block: MarkdownFormatting.table(rows: 1, columns: 2), select: cell)
        let text = apply(edit, to: "Intro")
        #expect(text == "Intro\n\n" + MarkdownFormatting.table(rows: 1, columns: 2) + "\n", "table goes below the line with a blank line before it")
        #expect(MarkdownFormatting.table(rows: 1, columns: 2) == "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |", "a 1×2 table")
        #expect(MarkdownFormatting.table(rows: 3, columns: 1) == "| Column 1 |\n| --- |\n|  |\n|  |\n|  |", "rows and columns follow the request")
        #expect(MarkdownFormatting.table(rows: 0, columns: 0) == "| Column 1 |\n| --- |", "at least one column, no body rows")
        #expect((text as NSString).substring(with: edit.selection) == "Column 1", "first header cell is selected")
    }

    @Test func blocksNeverTurnTheLineAboveIntoAHeadingAndFillBlankLines() {
        var edit = MarkdownFormatting.insertBlock("a\nb", selection: NSRange(location: 0, length: 0), block: MarkdownFormatting.rule)
        #expect(apply(edit, to: "a\nb") == "a\n\n---\n\nb", "a rule never turns the line above into a heading")
        edit = MarkdownFormatting.insertBlock("a\n\n", selection: NSRange(location: 2, length: 0), block: MarkdownFormatting.rule)
        #expect(apply(edit, to: "a\n\n") == "a\n\n---\n", "on a blank line the block fills it")
        #expect(edit.selection == NSRange(location: 7, length: 0), "caret lands on the line after the block")
        edit = MarkdownFormatting.insertBlock("", selection: NSRange(location: 0, length: 0), block: MarkdownFormatting.rule)
        #expect(apply(edit, to: "") == "---\n", "block in an empty note")
    }
}
