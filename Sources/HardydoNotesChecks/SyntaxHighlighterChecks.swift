import Foundation
import HardydoNotesCore

private func kinds(_ text: String, _ language: ContentLanguage) -> [String: SyntaxKind] {
    var result: [String: SyntaxKind] = [:]
    for token in SyntaxHighlighter.tokens(in: text, language: language) {
        result[(text as NSString).substring(with: token.range)] = token.kind
    }
    return result
}

func runHighlighterChecks() {
    let json = kinds(#"{"name": "a // b", "n": -1.5e3, "ok": true, "none": null}"#, .json)
    checkEqual(json["\"name\""], .property, "JSON keys")
    checkEqual(json["\"a // b\""], .string, "JSON strings hide comment marks")
    checkEqual(json["-1.5e3"], .number, "JSON numbers")
    checkEqual(json["true"], .literal, "JSON literals")
    checkEqual(json["null"], .literal, "JSON null")

    let js = kinds("// note\nconst url = \"http://x\"; let n = 42;\nconsole.log(`hi ${n}`)\nclass Box {}", .javascript)
    checkEqual(js["// note"], .comment, "JS line comment")
    checkEqual(js["const"], .keyword, "JS keyword")
    checkEqual(js["\"http://x\""], .string, "a URL inside a string is not a comment")
    checkEqual(js["42"], .number, "JS number")
    checkEqual(js["log"], .function, "JS call")
    checkEqual(js["`hi ${n}`"], .string, "JS template string")
    checkEqual(js["Box"], .type, "JS class name")
    check(js["url"] == nil, "plain identifiers stay uncoloured")

    let ts = kinds("interface User { name: string }", .typescript)
    checkEqual(ts["interface"], .keyword, "TS keyword")
    checkEqual(ts["string"], .type, "TS built-in type")

    let py = kinds("@cache\ndef load(path):\n    \"\"\"Read it.\"\"\"\n    return None  # nothing\nclass Store(Base): pass", .python)
    checkEqual(py["@cache"], .attribute, "Python decorator")
    checkEqual(py["def"], .keyword, "Python keyword")
    checkEqual(py["load"], .function, "Python function name")
    checkEqual(py["\"\"\"Read it.\"\"\""], .string, "Python docstring")
    checkEqual(py["None"], .literal, "Python literal")
    checkEqual(py["# nothing"], .comment, "Python comment")
    checkEqual(py["Store"], .type, "Python class name")

    let swift = kinds("@MainActor final class Box: View { let x: Int = 0x1F // hex\n}", .swift)
    checkEqual(swift["@MainActor"], .attribute, "Swift attribute")
    checkEqual(swift["final"], .keyword, "Swift keyword")
    checkEqual(swift["View"], .type, "Swift type")
    checkEqual(swift["0x1F"], .number, "Swift hex number")
    checkEqual(swift["// hex"], .comment, "Swift comment")

    let html = kinds("<!-- c -->\n<a href=\"/x\" hidden>Hi \"there\"</a>&amp;\n<style>p { color: red; }</style>", .html)
    checkEqual(html["<!-- c -->"], .comment, "HTML comment")
    checkEqual(html["a"], .tag, "HTML tag name")
    checkEqual(html["href"], .attribute, "HTML attribute")
    checkEqual(html["\"/x\""], .string, "HTML attribute value")
    check(html["\"there\""] == nil, "quotes in page text are not strings")
    checkEqual(html["&amp;"], .literal, "HTML entity")
    checkEqual(html["color"], .property, "CSS inside a style tag is coloured")

    let css = kinds(".card:hover {\n  color: #fff;\n  margin: 4px 0;\n}\n@media screen {}", .css)
    checkEqual(css[".card:hover "], .tag, "CSS selector")
    checkEqual(css["color"], .property, "CSS property")
    checkEqual(css["#fff"], .number, "CSS colour")
    checkEqual(css["4px"], .number, "CSS length")
    checkEqual(css["@media"], .keyword, "CSS at-rule")

    let yaml = kinds("# config\nname: \"demo\"\nitems:\n  - id: 3\n    enabled: true\n", .yaml)
    checkEqual(yaml["# config"], .comment, "YAML comment")
    checkEqual(yaml["name"], .property, "YAML key")
    checkEqual(yaml["id"], .property, "YAML key inside a list item")
    checkEqual(yaml["\"demo\""], .string, "YAML string")
    checkEqual(yaml["true"], .literal, "YAML literal")
    checkEqual(yaml["3"], .number, "YAML number")

    let sql = kinds("select name from users where note = 'it''s' -- done\n", .sql)
    checkEqual(sql["select"], .keyword, "SQL keywords ignore case")
    checkEqual(sql["'it''s'"], .string, "SQL string with doubled quote")
    checkEqual(sql["-- done"], .comment, "SQL comment")

    let shell = kinds("# setup\nexport PATH=\"$HOME/bin\"\nif [ -n \"$1\" ]; then git pull --rebase; fi", .shell)
    checkEqual(shell["# setup"], .comment, "shell comment")
    checkEqual(shell["export"], .keyword, "shell keyword")
    checkEqual(shell["\"$HOME/bin\""], .string, "shell string")
    checkEqual(shell["git"], .function, "shell command")
    checkEqual(shell["--rebase"], .attribute, "shell flag")

    let markdown = "# Title\nSome **bold** text\n```json\n{\"a\": 1}\n```\n```\nplain\n```"
    let md = kinds(markdown, .markdown)
    checkEqual(md["\"a\""], .property, "a fenced block is coloured in its own language")
    checkEqual(md["```json"], .punctuation, "fence lines are dimmed")
    checkEqual(md["```\nplain\n```"], .code, "a fence without a language is code")
    check(SyntaxHighlighter.tokens(in: markdown, language: .markdown).contains { $0.kind == .heading }, "Markdown headings")
    check(SyntaxHighlighter.tokens(in: "plain words", language: .plainText).isEmpty, "plain text has no colours")
}
