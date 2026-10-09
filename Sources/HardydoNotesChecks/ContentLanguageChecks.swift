import Foundation
import HardydoNotesCore

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
