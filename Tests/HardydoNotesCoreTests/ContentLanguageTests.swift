import Foundation
import HardydoNotesCore
import Testing

private func detect(_ text: String, _ fileName: String? = nil) -> ContentLanguage {
    ContentLanguage.detect(text, fileName: fileName)
}

@Suite struct ContentLanguageTests {
    @Test func fileExtensionDecidesTheLanguage() {
        #expect(detect("", nil) == .markdown, "an empty note is Markdown")
        #expect(detect("anything", "data.json") == .json, "a file extension decides")
        #expect(detect("{}", "notes.md") == .markdown, "a Markdown file stays Markdown")
        #expect(detect("hello", "todo.txt") == .plainText, "a .txt file is plain text")
        #expect(detect("echo hi", ".zshrc") == .shell, "shell dotfiles are shell")
        #expect(detect("print('x')", "tool.unknown") == .markdown, "an unknown extension falls back to the content")
    }

    @Test func structuredDocumentsAndShebangsAreRecognised() {
        #expect(detect("{\n  \"name\": \"demo\",\n  \"tags\": [1, 2]\n}") == .json, "JSON object")
        #expect(detect("[{\"a\": 1}]") == .json, "JSON array")
        #expect(detect("{\"a\": ") == .json, "half-typed JSON is still JSON")
        #expect(detect("[Docs](https://example.com) explain the setup.") == .markdown, "a Markdown link is not JSON")
        #expect(detect("<!doctype html>\n<html><body><p>Hi</p></body></html>") == .html, "HTML page")
        #expect(detect("<div class=\"card\">\n  <span>Hi</span>\n</div>") == .html, "HTML fragment")
        #expect(detect("<?xml version=\"1.0\"?>\n<plist><dict/></plist>") == .xml, "XML document")
        #expect(detect("#!/usr/bin/env python3\nprint('hi')") == .python, "python shebang")
        #expect(detect("#!/bin/bash\nls") == .shell, "shell shebang")
    }

    @Test func sourceCodeIsRecognisedByContent() {
        #expect(detect("""
        import os
        from pathlib import Path

        def main(args):
            for item in args:
                if item:
                    print(item)

        class Runner:
            pass
        """) == .python, "Python code")
        #expect(detect("""
        import { useState } from 'react';

        export function Counter() {
          const [count, setCount] = useState(0);
          return count;
        }
        """) == .javascript, "JavaScript code")
        #expect(detect("""
        interface User {
          name: string;
          age: number;
        }
        export const users: User[] = [];
        """) == .typescript, "TypeScript code")
        #expect(detect("""
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
        """) == .typescript, "a TypeScript class with a switch and closing braces")
        #expect(detect("""
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
        """) == .javascript, "a JavaScript class without types")
        #expect(detect("""
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
        """) == .swift, "SwiftUI with trailing closures stays Swift")
        #expect(detect("""
        import SwiftUI

        struct ContentView: View {
            let title: String
            var body: some View {
                Text(title)
            }
        }
        """) == .swift, "Swift code")
        #expect(detect("""
        .card {
          color: #333;
          padding: 8px;
        }
        body {
          margin: 0;
        }
        """) == .css, "CSS")
        #expect(detect("""
        name: build
        on:
          push:
            branches: [main]
        jobs:
          test:
            runs-on: macos-latest
        """) == .yaml, "YAML")
        #expect(detect("""
        SELECT id, name
        FROM users
        WHERE active = 1
        ORDER BY name;
        """) == .sql, "SQL")
        #expect(detect("""
        export PATH="$HOME/bin:$PATH"
        cd ~/projects
        git pull && npm install
        echo "done"
        """) == .shell, "shell commands")
    }

    @Test func proseAndFencedCodeStayMarkdown() {
        #expect(detect("""
        # Weekly plan

        - Call the bank about the card
        - Finish the quarterly report draft
        Remember to book tickets for the trip next month.
        """) == .markdown, "a note with lists and prose is Markdown")
        #expect(detect("""
        Hôm nay họp với team về kế hoạch quý tới.
        Mọi người thống nhất ưu tiên sửa lỗi trước khi làm tính năng mới.
        Cần gửi biên bản cho chị Lan trước thứ sáu.
        """) == .markdown, "plain prose is Markdown")
        #expect(detect("""
        Notes from the meeting:
        ```js
        const a = 1;
        const b = 2;
        ```
        """) == .markdown, "code inside a fence keeps the note Markdown")
    }

    @Test func shortNotesThatLookLikeCodeStayMarkdown() {
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
            #expect(detect(text) == .markdown, "\(label) stay a note")
        }
    }

    @Test func halfTypedJSONYAMLSQLAndShellSnippets() {
        #expect(detect("[\n  1,\n  2") == .json, "a half-typed JSON array is still JSON")
        #expect(detect("---\nname: demo\nversion: 1") == .yaml, "a YAML document header")
        #expect(detect("- name: a\n  value: 1\n- name: b\n  value: 2") == .yaml, "a YAML list of maps")
        #expect(detect("UPDATE users SET active = 0\nWHERE id = 3;") == .sql, "an UPDATE statement")
        #expect(detect("ls -la\ncd \"$DIR\"\necho ${HOME}") == .shell, "shell variables")
    }

    @Test func fenceNamesMapToLanguages() {
        #expect(ContentLanguage.fenceLanguage("py") == .python, "fence names accept extensions")
        #expect(ContentLanguage.fenceLanguage("console") == .shell, "fence aliases")
        #expect(ContentLanguage.fenceLanguage("brainfuck") == nil, "unknown fences are not coloured")
    }
}
