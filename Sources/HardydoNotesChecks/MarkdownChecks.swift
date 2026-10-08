import HardydoNotesCore
import Foundation

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

private func styles(_ text: String, _ substring: String) -> [MarkdownStyle] {
    let range = (text as NSString).range(of: substring)
    return MarkdownStyler.spans(in: text).filter { NSEqualRanges($0.range, range) }.map(\.style)
}

func runStylerChecks() {
    let text = "# Title\nSome **bold** and *it* and `co*de*` ~~gone~~ [link](https://x.y)\n> quote\n- [x] done\n1. one"
    check(styles(text, "# Title").contains(.heading(1)), "heading span")
    check(styles(text, "**bold**").contains(.bold), "bold span")
    check(styles(text, "*it*").contains(.italic), "italic span")
    check(!styles(text, "**bold**").contains(.italic), "bold is not italic")
    check(styles(text, "`co*de*`").contains(.inlineCode), "inline code span")
    check(styles(text, "*de*").isEmpty, "no italic inside inline code")
    check(styles(text, "~~gone~~").contains(.strikethrough), "strikethrough span")
    check(styles(text, "link").contains(.link), "link text span")
    check(styles(text, "> quote").contains(.quote), "quote span")
    check(styles(text, "done").contains(.taskDone), "checked task content")
    check(styles(text, "1.").contains(.listMarker), "ordered list marker")

    let fenced = "```swift\nlet a = **b**\n```\nafter **x**"
    check(styles(fenced, "**b**").isEmpty, "no bold inside fenced code")
    check(styles(fenced, "**x**").contains(.bold), "bold after fenced code")
    check(styles(fenced, "```swift").contains(.syntax), "fence line dimmed")

    check(styles("snake_case_name", "_case_").isEmpty, "underscores inside words are not italic")
    check(styles("---", "---").contains(.syntax), "rule is dimmed")
    check(!styles("---", "-").contains(.listMarker), "rule is not a list")
}

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

func runJSONFormatterChecks() {
    checkEqual(try? JSONFormatter.format(#"{"b":1,"a":[1,2,{"x":"y, z: {"}],"e":{},"f":[]}"#), """
    {
      "b": 1,
      "a": [
        1,
        2,
        {
          "x": "y, z: {"
        }
      ],
      "e": {},
      "f": []
    }
    """, "JSON is indented with keys in their original order")
    checkEqual(try? JSONFormatter.format("{\n\"q\": \"say \\\"hi\\\"\", \"n\": 1.50e3}\n"), "{\n  \"q\": \"say \\\"hi\\\"\",\n  \"n\": 1.50e3\n}\n", "escaped quotes and number text are kept")
    checkEqual(try? JSONFormatter.format("  [ ]  "), "[]", "empty array")
    checkEqual(try? JSONFormatter.format("{\"a\":\"x\",\"b\u{301}\":\"e\u{301}\"}"), "{\n  \"a\": \"x\",\n  \"b\u{301}\": \"e\u{301}\"\n}", "a combining mark after a quote keeps strings intact")
    checkEqual(try? JSONFormatter.format("[\"👨‍👩‍👧\",\"\u{301}\"]"), "[\n  \"👨‍👩‍👧\",\n  \"\u{301}\"\n]", "a string starting with a combining mark")
    do {
        _ = try JSONFormatter.format("{\"a\": }")
        check(false, "invalid JSON is refused")
    } catch {
        check(error is JSONFormatError, "invalid JSON is refused")
    }
}

func runHTMLChecks() {
    let html = MarkdownHTML.body("""
    # Title

    | A | B |
    |---|---|
    | 1 | 2 |

    - [x] done
    - [ ] todo

    ~~old~~ https://example.com <script>alert(1)</script>

    ```swift
    let x = 1
    ```
    """)
    check(html.contains("<h1>Title</h1>"), "heading renders")
    check(html.contains("<table>") && html.contains("<td>1</td>"), "table renders")
    check(html.contains("type=\"checkbox\" checked=\"\" disabled=\"\""), "checked task renders as checkbox")
    check(html.contains("<del>old</del>"), "strikethrough renders")
    check(html.contains("<a href=\"https://example.com\">"), "bare URL becomes link")
    check(!html.contains("<script>"), "raw HTML is not rendered")
    check(html.contains("<code class=\"language-swift\">"), "fenced code keeps language")
    check(MarkdownHTML.page("Café déjà vu").contains("<p>Café déjà vu</p>"), "page wraps body with unicode intact")
    let content = MarkdownHTML.content("- [x] done")
    check(content.contains("checked=\"\"") && !content.contains("disabled"), "live content keeps checkboxes without disabled attribute")
    check(MarkdownHTML.page("x").contains("id=\"content\"") && MarkdownHTML.page("x").contains("function render(html)"), "page can be updated in place")
    checkEqual(MarkdownHTML.content("{\"a\": \"<b>\"}", language: .json), "<pre><code class=\"language-json\">{\"a\": \"&lt;b&gt;\"}</code></pre>", "code preview is one escaped, highlighted block")
    checkEqual(MarkdownHTML.content("<p>", language: .html), "<pre><code class=\"language-xml\">&lt;p&gt;</code></pre>", "HTML preview uses the highlight.js xml name")
    checkEqual(MarkdownHTML.content("# not a heading", language: .plainText), "<pre class=\"plain\"># not a heading</pre>", "plain text is shown as typed")
}

func runExportPageChecks() {
    let page = MarkdownHTML.page("# Hi", title: "Fish & <Chips>")
    check(page.contains("<title>Fish &amp; &lt;Chips&gt;</title>"), "exported page has an escaped title")
    check(!MarkdownHTML.page("# Hi").contains("<title>"), "preview page has no title")

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let highlighter = MarkdownHTML.Highlighter(directory: root.appending(path: "Resources/highlight"))
    check(highlighter != nil, "highlight.js and its themes ship with the app")
    let offline = MarkdownHTML.page("```swift\nlet a = 1\n```", highlighter: highlighter)
    check(offline.contains("var hljs=") && offline.contains("<style media=\"print\">"), "code highlighting is written into the page")
    check(!offline.contains("<link") && !offline.contains("cdnjs") && !offline.contains(".src ="), "the page loads nothing from the network")
}

func runTabChecks() {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    var tabs = TabList()
    tabs.open(a, keep: false)
    checkEqual(tabs.ids, [a], "first click opens a preview tab")
    checkEqual(tabs.preview, a, "single click tab is a preview")
    tabs.open(b, keep: false)
    check(tabs.ids == [b] && tabs.active == b, "next single click replaces the preview tab")
    tabs.keep(b)
    tabs.open(c, keep: false)
    check(tabs.ids == [b, c] && tabs.preview == c, "a kept tab stays when another note is clicked")
    tabs.open(b, keep: false)
    check(tabs.ids == [b, c] && tabs.active == b && tabs.preview == c, "clicking an open note reuses its tab")
    tabs.open(d, keep: true)
    checkEqual(tabs.ids, [b, d, c], "a kept tab opens right of the active one")
    check(tabs.preview == c, "opening a kept tab leaves the preview alone")
    tabs.open(c, keep: true)
    check(tabs.preview == nil && tabs.active == c, "keeping the preview tab makes it permanent")

    tabs.activate(d)
    tabs.close(d)
    checkEqual(tabs.active, c, "closing the active tab moves to its right")
    tabs.close(c)
    checkEqual(tabs.active, b, "closing the last tab moves to its left")
    tabs.close(b)
    check(tabs.ids.isEmpty && tabs.active == nil, "closing every tab leaves nothing active")

    tabs = TabList(ids: [a, b, c, d], active: b)
    tabs.closeRight(of: a)
    check(tabs.ids == [a] && tabs.active == a, "closing tabs to the right moves off a closed active tab")
    tabs = TabList(ids: [a, b, c], active: c)
    tabs.closeOthers(b)
    check(tabs.ids == [b] && tabs.active == b, "close others keeps only that tab")

    tabs = TabList(ids: [a, b, c], active: a)
    tabs.cycle(by: -1)
    checkEqual(tabs.active, c, "previous tab wraps around")
    tabs.cycle(by: 1)
    checkEqual(tabs.active, a, "next tab wraps around")
    tabs.reorder([b, c, a])
    checkEqual(tabs.ids, [b, c, a], "a dragged tab lands where it was dropped")

    tabs = TabList(ids: [a, b, c], active: b)
    tabs.prune(keeping: [a, c])
    check(tabs.ids == [a, c] && tabs.active == c, "tabs of vanished notes close and the active tab moves on")
    checkEqual(TabList(ids: [a, b], active: d).active, a, "restored tabs fall back to the first tab")
}
