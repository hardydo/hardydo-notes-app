import HardydoNotesCore
import Foundation

func runLanguageChecks() {
    func detect(_ text: String, _ fileName: String? = nil) -> ContentLanguage {
        ContentLanguage.detect(text, fileName: fileName)
    }
    checkEqual(detect("", nil), .markdown, "an empty note is Markdown")
    checkEqual(detect("anything", "data.json"), .json, "a file extension decides")
    checkEqual(detect("{}", "notes.md"), .markdown, "a Markdown file stays Markdown")
    checkEqual(detect("hello", "todo.txt"), .plainText, "a .txt file is plain text")
    checkEqual(detect("echo hi", ".zshrc"), .shell, "shell dotfiles are shell")
    checkEqual(detect("print('x')", "tool.unknown"), .markdown, "an unknown extension falls back to the content")

    checkEqual(detect("{\n  \"name\": \"demo\",\n  \"tags\": [1, 2]\n}"), .json, "JSON object")
    checkEqual(detect("[{\"a\": 1}]"), .json, "JSON array")
    checkEqual(detect("{\"a\": "), .json, "half-typed JSON is still JSON")
    checkEqual(detect("[Docs](https://example.com) explain the setup."), .markdown, "a Markdown link is not JSON")
    checkEqual(detect("<!doctype html>\n<html><body><p>Hi</p></body></html>"), .html, "HTML page")
    checkEqual(detect("<div class=\"card\">\n  <span>Hi</span>\n</div>"), .html, "HTML fragment")
    checkEqual(detect("<?xml version=\"1.0\"?>\n<plist><dict/></plist>"), .xml, "XML document")
    checkEqual(detect("#!/usr/bin/env python3\nprint('hi')"), .python, "python shebang")
    checkEqual(detect("#!/bin/bash\nls"), .shell, "shell shebang")

    checkEqual(detect("""
    import os
    from pathlib import Path

    def main(args):
        for item in args:
            if item:
                print(item)

    class Runner:
        pass
    """), .python, "Python code")
    checkEqual(detect("""
    import { useState } from 'react';

    export function Counter() {
      const [count, setCount] = useState(0);
      return count;
    }
    """), .javascript, "JavaScript code")
    checkEqual(detect("""
    interface User {
      name: string;
      age: number;
    }
    export const users: User[] = [];
    """), .typescript, "TypeScript code")
    checkEqual(detect("""
    export class AuthProviderFactory {
      static createProvider(type: AuthProviderType, config: AuthConfig): IAuthProvider {
        switch (type) {
          case "keycloak":
            return new KeycloakProvider(config);
          default:
            throw new Error(`Unknown provider type: ${type}`);
        }
      }
      static getConfigFromEnv(configKey = "VITE_KC_AUTH_CONFIG"): AuthConfig {
        const kcConfig = JSON.parse(import.meta.env[configKey] || "{}");
        return {
          serverUrl: kcConfig.serverUrl,
        };
      }
    }
    """), .typescript, "a TypeScript class with a switch and closing braces")
    checkEqual(detect("""
    class Queue {
      constructor(limit) {
        this.items = [];
      }
      push(item) {
        switch (item.kind) {
          case "drop":
            return;
          default:
            this.items.push(item);
        }
      }
    }
    """), .javascript, "a JavaScript class without types")
    checkEqual(detect("""
    import SwiftUI

    struct RowView: View {
        let note: Note
        let onClose: () -> Void

        func close() {
            onClose()
        }

        var body: some View {
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                Text(note.title)
            }
            .padding(.vertical, 7)
        }
    }
    """), .swift, "SwiftUI with trailing closures stays Swift")
    checkEqual(detect("""
    import SwiftUI

    struct ContentView: View {
        let title: String
        var body: some View {
            Text(title)
        }
    }
    """), .swift, "Swift code")
    checkEqual(detect("""
    .card {
      color: #333;
      padding: 8px;
    }
    body {
      margin: 0;
    }
    """), .css, "CSS")
    checkEqual(detect("""
    name: build
    on:
      push:
        branches: [main]
    jobs:
      test:
        runs-on: macos-latest
    """), .yaml, "YAML")
    checkEqual(detect("""
    SELECT id, name
    FROM users
    WHERE active = 1
    ORDER BY name;
    """), .sql, "SQL")
    checkEqual(detect("""
    export PATH="$HOME/bin:$PATH"
    cd ~/projects
    git pull && npm install
    echo "done"
    """), .shell, "shell commands")

    checkEqual(detect("""
    # Weekly plan

    - Call the bank about the card
    - Finish the quarterly report draft
    Remember to book tickets for the trip next month.
    """), .markdown, "a note with lists and prose is Markdown")
    checkEqual(detect("""
    Hôm nay họp với team về kế hoạch quý tới.
    Mọi người thống nhất ưu tiên sửa lỗi trước khi làm tính năng mới.
    Cần gửi biên bản cho chị Lan trước thứ sáu.
    """), .markdown, "plain prose is Markdown")
    checkEqual(detect("""
    Notes from the meeting:
    ```js
    const a = 1;
    const b = 2;
    ```
    """), .markdown, "code inside a fence keeps the note Markdown")
    let notes: [(String, String)] = [
        ("[2025-10-07] gọi ngân hàng\n[2025-10-08] nộp báo cáo", "date-stamped lines"),
        ("[ ] mua sữa\n[ ] đón con", "bare checkboxes"),
        ("[fix] lỗi đăng nhập\n[feat] trang mới", "tagged lines"),
        ("[link](https://example.com)", "a lowercase Markdown link"),
        ("{draft}\nÝ tưởng cho bài viết", "a note starting with a brace"),
        ("Wifi: CafeX\nPass: 12345678\nGiờ mở cửa: 7h", "key-value notes"),
        ("Update CV\nOrder pizza\nSet lịch họp", "to-do lines starting with SQL words"),
        ("Giá $5 một ly\nTổng $20 cho bốn ly", "prices with a dollar sign"),
        ("Hà Nội => Huế\nHuế => Đà Nẵng", "arrows between words"),
        ("<b>Chú ý</b> mang theo áo mưa\nNhớ khoá cửa", "a note starting with inline HTML"),
    ]
    for (text, label) in notes {
        checkEqual(detect(text), .markdown, "\(label) stay a note")
    }
    checkEqual(detect("[\n  1,\n  2"), .json, "a half-typed JSON array is still JSON")
    checkEqual(detect("---\nname: demo\nversion: 1"), .yaml, "a YAML document header")
    checkEqual(detect("- name: a\n  value: 1\n- name: b\n  value: 2"), .yaml, "a YAML list of maps")
    checkEqual(detect("UPDATE users SET active = 0\nWHERE id = 3;"), .sql, "an UPDATE statement")
    checkEqual(detect("ls -la\ncd \"$DIR\"\necho ${HOME}"), .shell, "shell variables")
    checkEqual(ContentLanguage.fenceLanguage("py"), .python, "fence names accept extensions")
    checkEqual(ContentLanguage.fenceLanguage("console"), .shell, "fence aliases")
    checkEqual(ContentLanguage.fenceLanguage("brainfuck"), nil, "unknown fences are not coloured")
}

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

func runFoldingChecks() {
    func regions(_ text: String, _ language: ContentLanguage) -> [String] {
        CodeFolding.regions(in: text, language: language).map { "\($0.startLine)-\($0.endLine)" }
    }
    checkEqual(regions("{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": \"{\"\n}", .json), ["0-5", "1-3"], "JSON objects and arrays fold, closing lines stay visible")
    checkEqual(regions("function a() {\n  // }\n  const s = \"}\";\n  return 1;\n}", .javascript), ["0-3"], "brackets in comments and strings are ignored")
    checkEqual(regions("const a = { b: 1 };\nlet c = [\n];", .javascript), [], "one-line and empty blocks do not fold")
    checkEqual(regions("def f(x):\n    if x:\n        return 1\n\n    return 2\n\nprint(f(1))", .python), ["0-4", "1-2"], "Python folds by indentation, trailing blank lines stay outside")
    checkEqual(regions("a:\n  b: 1\n  c:\n    - d\ne: 2", .yaml), ["0-3", "2-3"], "YAML folds by indentation")
    checkEqual(regions("if [ -n \"$1\" ]; then\n\techo hi\nfi", .shell), ["0-1"], "tabs count as indentation")
    checkEqual(regions("# A\ntext\n## B\nmore\n\n# C\n```js\nx\ny\n```\nend", .markdown), ["0-3", "2-3", "5-10", "6-9"], "Markdown headings fold to the next heading of the same level; a fence folds through its closing line")
    checkEqual(regions("", .json), [], "empty text has no regions")
}

func runFoldingEdgeChecks() {
    func regions(_ text: String, _ language: ContentLanguage) -> [String] {
        CodeFolding.regions(in: text, language: language).map { "\($0.startLine)-\($0.endLine)" }
    }
    checkEqual(regions("{\n  \"a[\": [\n    1\n  ],\n  \"b\": 2\n}", .json), ["0-4", "1-2"], "a bracket inside a JSON key does not break pairing")
    checkEqual(regions("````md\n```js\nx\n```\n````\nend", .markdown), ["0-4"], "a longer fence is not closed by a shorter one inside it")
    checkEqual(regions("switch (t) {\n  case \"a\":\n    return 1;\n  case \"b\":\n  case \"c\":\n    x();\n    y();\n\n  default:\n    z();\n}", .javascript), ["0-9", "1-2", "4-6", "8-9"], "case clauses fold to their last statement; empty clauses do not fold")
    checkEqual(regions("switch x {\ncase .a:\n    f()\n    g()\ndefault:\n    h()\n}", .swift), ["0-5", "1-3", "4-5"], "Swift case clauses fold")
    checkEqual(regions("import a from \"a\";\nimport {\n  b,\n} from \"b\";\n\n// one\n// two\nconst x = 1;\n/*\n block\n*/\n// #region tools\nconst y = 2;\n// #endregion", .typescript), ["0-3", "1-2", "5-6", "8-10", "11-13"], "imports, line comment runs, block comments and regions fold")
    checkEqual(regions("const s = `a\nb\nc`;", .javascript), ["0-1"], "a template string folds with its closing line visible")
    checkEqual(regions("a\n  b\n\nc", .plainText), ["0-2"], "indentation blocks keep trailing blank lines outside off-side languages")
    checkEqual(regions("# region x\na = 1\nb = 2\n# endregion", .python), ["0-3"], "region markers fold through the end marker")
    checkEqual(regions("- a\n  b\n- c\n\n| h | i |\n| - | - |\n| 1 | 2 |\n\n> q\n> r", .markdown), ["0-1", "4-6", "8-9"], "multi-line list items, tables and block quotes fold")
    checkEqual(regions("Title\n=====\ntext\n\nSub\n---\nmore", .markdown), ["0-6", "4-6"], "setext headings fold like ATX headings")
    checkEqual(regions("<!-- #region -->\na\n<!-- #endregion -->", .markdown), ["0-2"], "Markdown region comments fold")
}

func runOutlineChecks() {
    let text = "# Guide\nintro\n## Setup ##\n```\n# not a heading\n```\n### Install\nstep\n\nOverview\n--------\n| # a |\n|---|\n## Usage"
    let headings = CodeFolding.markdownHeadings(in: text)
    checkEqual(headings.map(\.title), ["Guide", "Setup", "Install", "Overview", "Usage"], "headings skip fences and tables and drop closing hashes")
    checkEqual(headings.map(\.level), [1, 2, 3, 2, 2], "heading levels include setext underlines")
    let path = { (line: Int) in CodeFolding.headingPath(headings, toLine: line).map(\.title) }
    checkEqual(path(1), ["Guide"], "text under a heading sits inside it")
    checkEqual(path(7), ["Guide", "Setup", "Install"], "nested headings form the path")
    checkEqual(path(9), ["Guide", "Overview"], "a sibling heading replaces the deeper ones")
    checkEqual(CodeFolding.headingPath(CodeFolding.markdownHeadings(in: "text\n# Late"), toLine: 0), [], "lines before the first heading have no path")
}
