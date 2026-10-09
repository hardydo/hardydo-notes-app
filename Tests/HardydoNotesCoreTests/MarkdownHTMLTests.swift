import Foundation
import HardydoNotesCore
import Testing

private func shippedHighlighter(file: String = #filePath) -> MarkdownHTML.Highlighter? {
    let root = URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return MarkdownHTML.Highlighter(directory: root.appending(path: "Resources/highlight"))
}

@Suite struct MarkdownHTMLTests {
    @Test func markdownElementsRender() {
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
        #expect(html.contains("<h1>Title</h1>"), "heading renders")
        #expect(html.contains("<table>") && html.contains("<td>1</td>"), "table renders")
        #expect(html.contains("type=\"checkbox\" checked=\"\" disabled=\"\""), "checked task renders as checkbox")
        #expect(html.contains("<del>old</del>"), "strikethrough renders")
        #expect(html.contains("<a href=\"https://example.com\">"), "bare URL becomes link")
        #expect(!html.contains("<script>"), "raw HTML is not rendered")
        #expect(html.contains("<code class=\"language-swift\">"), "fenced code keeps language")
    }

    @Test func pageWrapsTheBodyAndCanBeUpdatedInPlace() {
        #expect(MarkdownHTML.page("Café déjà vu").contains("<p>Café déjà vu</p>"), "page wraps body with unicode intact")
        let content = MarkdownHTML.content("- [x] done")
        #expect(content.contains("checked=\"\"") && !content.contains("disabled"), "live content keeps checkboxes without disabled attribute")
        #expect(MarkdownHTML.page("x").contains("id=\"content\"") && MarkdownHTML.page("x").contains("function render(html)"), "page can be updated in place")
    }

    @Test func codePreviewIsOneEscapedBlock() {
        #expect(MarkdownHTML.content("{\"a\": \"<b>\"}", language: .json) == "<pre><code class=\"language-json\">{\"a\": \"&lt;b&gt;\"}</code></pre>", "code preview is one escaped, highlighted block")
        #expect(MarkdownHTML.content("<p>", language: .html) == "<pre><code class=\"language-xml\">&lt;p&gt;</code></pre>", "HTML preview uses the highlight.js xml name")
        #expect(MarkdownHTML.content("# not a heading", language: .plainText) == "<pre class=\"plain\"># not a heading</pre>", "plain text is shown as typed")
    }

    @Test func codePastTheHighlightLimitShowsUncoloured() {
        let longCode = String(repeating: "x", count: 1_000)
        #expect(MarkdownHTML.content(longCode, language: .json, highlightLimit: 999).hasPrefix("<pre class=\"plain\">"), "code past the highlight limit shows uncoloured")
        #expect(MarkdownHTML.content(longCode, language: .json, highlightLimit: 1_000).contains("language-json"), "code at the highlight limit is still coloured")
    }

    @Test func exportedPageHasAnEscapedTitle() {
        let page = MarkdownHTML.page("# Hi", title: "Fish & <Chips>")
        #expect(page.contains("<title>Fish &amp; &lt;Chips&gt;</title>"), "exported page has an escaped title")
        #expect(!MarkdownHTML.page("# Hi").contains("<title>"), "preview page has no title")
    }

    @Test func highlightAssetsShipWithTheApp() {
        let highlighter = shippedHighlighter()
        #expect(highlighter != nil, "highlight.js and its themes ship with the app")
    }

    @Test func exportedPageCarriesHighlightingAndLoadsNothingFromTheNetwork() {
        let highlighter = shippedHighlighter()
        let offline = MarkdownHTML.page("```swift\nlet a = 1\n```", highlighter: highlighter)
        #expect(offline.contains("var hljs=") && offline.contains("<style media=\"print\">"), "code highlighting is written into the page")
        #expect(!offline.contains("<link") && !offline.contains("cdnjs") && !offline.contains(".src ="), "the page loads nothing from the network")
    }
}
