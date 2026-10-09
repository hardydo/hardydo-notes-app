import Foundation
import HardydoNotesCore
import Testing

private func styles(_ text: String, _ substring: String) -> [MarkdownStyle] {
    let range = (text as NSString).range(of: substring)
    return MarkdownStyler.spans(in: text).filter { NSEqualRanges($0.range, range) }.map(\.style)
}

@Suite struct MarkdownStylerTests {
    @Test func inlineAndBlockMarkdownIsStyled() {
        let text = "# Title\nSome **bold** and *it* and `co*de*` ~~gone~~ [link](https://x.y)\n> quote\n- [x] done\n1. one"
        #expect(styles(text, "# Title").contains(.heading(1)), "heading span")
        #expect(styles(text, "**bold**").contains(.bold), "bold span")
        #expect(styles(text, "*it*").contains(.italic), "italic span")
        #expect(!styles(text, "**bold**").contains(.italic), "bold is not italic")
        #expect(styles(text, "`co*de*`").contains(.inlineCode), "inline code span")
        #expect(styles(text, "*de*").isEmpty, "no italic inside inline code")
        #expect(styles(text, "~~gone~~").contains(.strikethrough), "strikethrough span")
        #expect(styles(text, "link").contains(.link), "link text span")
        #expect(styles(text, "> quote").contains(.quote), "quote span")
        #expect(styles(text, "done").contains(.taskDone), "checked task content")
        #expect(styles(text, "1.").contains(.listMarker), "ordered list marker")
    }

    @Test func fencedCodeIsNotStyledAsMarkdown() {
        let fenced = "```swift\nlet a = **b**\n```\nafter **x**"
        #expect(styles(fenced, "**b**").isEmpty, "no bold inside fenced code")
        #expect(styles(fenced, "**x**").contains(.bold), "bold after fenced code")
        #expect(styles(fenced, "```swift").contains(.syntax), "fence line dimmed")
    }

    @Test func wordInternalUnderscoresAndRules() {
        #expect(styles("snake_case_name", "_case_").isEmpty, "underscores inside words are not italic")
        #expect(styles("---", "---").contains(.syntax), "rule is dimmed")
        #expect(!styles("---", "-").contains(.listMarker), "rule is not a list")
    }
}
