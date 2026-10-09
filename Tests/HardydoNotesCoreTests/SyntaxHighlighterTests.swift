import Foundation
import HardydoNotesCore
import Testing

private func kinds(_ text: String, _ language: ContentLanguage) -> [String: SyntaxKind] {
    var result: [String: SyntaxKind] = [:]
    for token in SyntaxHighlighter.tokens(in: text, language: language) {
        result[(text as NSString).substring(with: token.range)] = token.kind
    }
    return result
}

@Suite struct SyntaxHighlighterTests {
    @Test func jsonKeysStringsNumbersAndLiterals() {
        let json = kinds(#"{"name": "a // b", "n": -1.5e3, "ok": true, "none": null}"#, .json)
        #expect(json["\"name\""] == .property, "JSON keys")
        #expect(json["\"a // b\""] == .string, "JSON strings hide comment marks")
        #expect(json["-1.5e3"] == .number, "JSON numbers")
        #expect(json["true"] == .literal, "JSON literals")
        #expect(json["null"] == .literal, "JSON null")
    }

    @Test func javaScriptCommentsKeywordsStringsAndTemplates() {
        let js = kinds("// note\nconst url = \"http://x\"; let n = 42;\nconsole.log(`hi ${n}`)\nclass Box {}", .javascript)
        #expect(js["// note"] == .comment, "JS line comment")
        #expect(js["const"] == .keyword, "JS keyword")
        #expect(js["\"http://x\""] == .string, "a URL inside a string is not a comment")
        #expect(js["42"] == .number, "JS number")
        #expect(js["log"] == .function, "JS call")
        #expect(js["`hi ${n}`"] == .string, "JS template string")
        #expect(js["Box"] == .type, "JS class name")
        #expect(js["url"] == nil, "plain identifiers stay uncoloured")
    }

    @Test func typeScriptKeywordsAndBuiltInTypes() {
        let ts = kinds("interface User { name: string }", .typescript)
        #expect(ts["interface"] == .keyword, "TS keyword")
        #expect(ts["string"] == .type, "TS built-in type")
    }

    @Test func pythonDecoratorsKeywordsDocstringsAndComments() {
        let py = kinds("@cache\ndef load(path):\n    \"\"\"Read it.\"\"\"\n    return None  # nothing\nclass Store(Base): pass", .python)
        #expect(py["@cache"] == .attribute, "Python decorator")
        #expect(py["def"] == .keyword, "Python keyword")
        #expect(py["load"] == .function, "Python function name")
        #expect(py["\"\"\"Read it.\"\"\""] == .string, "Python docstring")
        #expect(py["None"] == .literal, "Python literal")
        #expect(py["# nothing"] == .comment, "Python comment")
        #expect(py["Store"] == .type, "Python class name")
    }

    @Test func swiftAttributesKeywordsTypesAndNumbers() {
        let swift = kinds("@MainActor final class Box: View { let x: Int = 0x1F // hex\n}", .swift)
        #expect(swift["@MainActor"] == .attribute, "Swift attribute")
        #expect(swift["final"] == .keyword, "Swift keyword")
        #expect(swift["View"] == .type, "Swift type")
        #expect(swift["0x1F"] == .number, "Swift hex number")
        #expect(swift["// hex"] == .comment, "Swift comment")
    }

    @Test func htmlTagsAttributesEntitiesAndEmbeddedCSS() {
        let html = kinds("<!-- c -->\n<a href=\"/x\" hidden>Hi \"there\"</a>&amp;\n<style>p { color: red; }</style>", .html)
        #expect(html["<!-- c -->"] == .comment, "HTML comment")
        #expect(html["a"] == .tag, "HTML tag name")
        #expect(html["href"] == .attribute, "HTML attribute")
        #expect(html["\"/x\""] == .string, "HTML attribute value")
        #expect(html["\"there\""] == nil, "quotes in page text are not strings")
        #expect(html["&amp;"] == .literal, "HTML entity")
        #expect(html["color"] == .property, "CSS inside a style tag is coloured")
    }

    @Test func cssSelectorsPropertiesColoursAndAtRules() {
        let css = kinds(".card:hover {\n  color: #fff;\n  margin: 4px 0;\n}\n@media screen {}", .css)
        #expect(css[".card:hover "] == .tag, "CSS selector")
        #expect(css["color"] == .property, "CSS property")
        #expect(css["#fff"] == .number, "CSS colour")
        #expect(css["4px"] == .number, "CSS length")
        #expect(css["@media"] == .keyword, "CSS at-rule")
    }

    @Test func yamlKeysStringsAndLiterals() {
        let yaml = kinds("# config\nname: \"demo\"\nitems:\n  - id: 3\n    enabled: true\n", .yaml)
        #expect(yaml["# config"] == .comment, "YAML comment")
        #expect(yaml["name"] == .property, "YAML key")
        #expect(yaml["id"] == .property, "YAML key inside a list item")
        #expect(yaml["\"demo\""] == .string, "YAML string")
        #expect(yaml["true"] == .literal, "YAML literal")
        #expect(yaml["3"] == .number, "YAML number")
    }

    @Test func sqlKeywordsStringsAndComments() {
        let sql = kinds("select name from users where note = 'it''s' -- done\n", .sql)
        #expect(sql["select"] == .keyword, "SQL keywords ignore case")
        #expect(sql["'it''s'"] == .string, "SQL string with doubled quote")
        #expect(sql["-- done"] == .comment, "SQL comment")
    }

    @Test func shellCommentsKeywordsStringsAndFlags() {
        let shell = kinds("# setup\nexport PATH=\"$HOME/bin\"\nif [ -n \"$1\" ]; then git pull --rebase; fi", .shell)
        #expect(shell["# setup"] == .comment, "shell comment")
        #expect(shell["export"] == .keyword, "shell keyword")
        #expect(shell["\"$HOME/bin\""] == .string, "shell string")
        #expect(shell["git"] == .function, "shell command")
        #expect(shell["--rebase"] == .attribute, "shell flag")
    }

    @Test func markdownFencesAreColouredInTheirOwnLanguage() {
        let markdown = "# Title\nSome **bold** text\n```json\n{\"a\": 1}\n```\n```\nplain\n```"
        let md = kinds(markdown, .markdown)
        #expect(md["\"a\""] == .property, "a fenced block is coloured in its own language")
        #expect(md["```json"] == .punctuation, "fence lines are dimmed")
        #expect(md["```\nplain\n```"] == .code, "a fence without a language is code")
        #expect(SyntaxHighlighter.tokens(in: markdown, language: .markdown).contains { $0.kind == .heading }, "Markdown headings")
        #expect(SyntaxHighlighter.tokens(in: "plain words", language: .plainText).isEmpty, "plain text has no colours")
    }
}
