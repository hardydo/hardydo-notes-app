import Foundation
import HardydoNotesCore

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
    let longCode = String(repeating: "x", count: 1_000)
    check(MarkdownHTML.content(longCode, language: .json, highlightLimit: 999).hasPrefix("<pre class=\"plain\">"), "code past the highlight limit shows uncoloured")
    check(MarkdownHTML.content(longCode, language: .json, highlightLimit: 1_000).contains("language-json"), "code at the highlight limit is still coloured")
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
