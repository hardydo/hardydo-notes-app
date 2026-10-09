import Foundation
import HardydoNotesCore

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
