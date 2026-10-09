import Foundation

public enum ContentLanguage: String, CaseIterable, Sendable {
    case markdown
    case plainText
    case json
    case javascript
    case typescript
    case python
    case html
    case xml
    case css
    case yaml
    case sql
    case shell
    case swift

    public var name: String {
        switch self {
        case .markdown: "Markdown"
        case .plainText: "Plain Text"
        case .json: "JSON"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .python: "Python"
        case .html: "HTML"
        case .xml: "XML"
        case .css: "CSS"
        case .yaml: "YAML"
        case .sql: "SQL"
        case .shell: "Shell"
        case .swift: "Swift"
        }
    }

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .json: "json"
        case .javascript: "js"
        case .typescript: "ts"
        case .python: "py"
        case .html: "html"
        case .xml: "xml"
        case .css: "css"
        case .yaml: "yaml"
        case .sql: "sql"
        case .shell: "sh"
        case .swift: "swift"
        }
    }

    /// The highlight.js name used by the preview page.
    public var highlightName: String? {
        switch self {
        case .markdown, .plainText: nil
        case .html: "xml"
        case .shell: "bash"
        default: rawValue
        }
    }

    private static let extensions: [String: ContentLanguage] = [
        "md": .markdown, "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
        "txt": .plainText, "text": .plainText, "log": .plainText,
        "json": .json, "jsonc": .json, "geojson": .json, "webmanifest": .json,
        "js": .javascript, "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript, "cts": .typescript,
        "py": .python, "pyw": .python,
        "html": .html, "htm": .html, "xhtml": .html,
        "xml": .xml, "plist": .xml, "svg": .xml, "xsd": .xml, "xsl": .xml,
        "css": .css, "scss": .css, "less": .css,
        "yaml": .yaml, "yml": .yaml,
        "sql": .sql,
        "sh": .shell, "bash": .shell, "zsh": .shell, "command": .shell,
        "swift": .swift,
    ]

    private static let fileNames: [String: ContentLanguage] = [
        ".zshrc": .shell, ".bashrc": .shell, ".bash_profile": .shell, ".zprofile": .shell, ".profile": .shell,
    ]

    /// Like VS Code: a file's extension decides; otherwise the content is sniffed, and notes default to Markdown.
    public static func detect(_ text: String, fileName: String? = nil) -> ContentLanguage {
        if let fileName {
            let lower = fileName.lowercased()
            if let known = fileNames[lower] { return known }
            let ext = (lower as NSString).pathExtension
            if let known = extensions[ext] { return known }
        }
        return sniff(text)
    }

    /// The language named after a Markdown code fence, such as ```json or ```py.
    public static func fenceLanguage(_ info: String) -> ContentLanguage? {
        let name = info.lowercased()
        guard !name.isEmpty else { return nil }
        return ContentLanguage(rawValue: name) ?? extensions[name] ?? fenceAliases[name]
    }

    private static let fenceAliases: [String: ContentLanguage] = [
        "console": .shell, "shellscript": .shell, "text": .plainText, "plaintext": .plainText, "postgres": .sql, "postgresql": .sql, "mysql": .sql,
    ]

    private static let sampleLength = 20_000
    private static let sampleLines = 200

    static func sniff(_ text: String) -> ContentLanguage {
        let sample = String(text.prefix(sampleLength))
        let trimmed = sample.drop { $0.isWhitespace || $0.isNewline }
        guard let first = trimmed.first else { return .markdown }

        let firstLine = String(trimmed.prefix { !$0.isNewline }.prefix(lineLimit))
        if (first == "{" || first == "[") && looksLikeJSON(text, sample: sample, firstLine: firstLine) { return .json }
        if first == "<" {
            let lower = trimmed.prefix(300).lowercased()
            let lowerRange = NSRange(location: 0, length: (lower as NSString).length)
            if lower.hasPrefix("<?xml") { return htmlTags.firstMatch(in: lower, range: lowerRange) == nil ? .xml : .html }
            if lower.hasPrefix("<!doctype html") { return .html }
            if matches(markupFirstLine, firstLine) {
                return htmlTags.firstMatch(in: lower, range: lowerRange) == nil ? .xml : .html
            }
        }
        if trimmed.hasPrefix("#!") {
            let line = trimmed.prefix { !$0.isNewline }
            if line.contains("python") { return .python }
            if line.contains("node") || line.contains("deno") { return .javascript }
            return .shell
        }
        if sample.contains("```") { return .markdown }

        // Lines holding only closing brackets say nothing about the language, so they do not count toward the share.
        let lineArray = nonEmptyLines(sample).filter { !matches(closingBrackets, $0) }
        guard !lineArray.isEmpty else { return .markdown }

        var counts: [ContentLanguage: Int] = [:]
        for line in lineArray {
            for (language, patterns) in linePatterns where patterns.contains(where: { matches($0, line) }) {
                counts[language, default: 0] += 1
            }
        }
        if counts[.typescript, default: 0] > 0, counts[.javascript, default: 0] > 0 {
            counts[.typescript, default: 0] += counts[.javascript, default: 0]
        }
        let markdown = counts[.markdown, default: 0]
        let needed = max(2, Int((Double(lineArray.count) * 0.4).rounded(.up)))
        let best = counts
            .filter { $0.key != .markdown && $0.value >= needed && $0.value > markdown }
            .filter { language, _ in shapes[language].map { matches($0, sample) } ?? true }
            .max { $0.value == $1.value ? priority($0.key) > priority($1.key) : $0.value < $1.value }
        return best?.key ?? .markdown
    }

    // Long lines are cut so a minified line cannot make every keystroke slow.
    private static let lineLimit = 500
    private static let jsonParseLimit = 512_000

    private static func nonEmptyLines(_ sample: String) -> [String] {
        Array(sample.split(whereSeparator: \.isNewline)
            .lazy.filter { !$0.allSatisfy(\.isWhitespace) }
            .prefix(sampleLines)
            .map { String($0.prefix(lineLimit)) })
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // Text that parses is JSON; while it is still being typed, its lines must look like JSON rather than a note starting with "[ ]" or "[2025]".
    private static func looksLikeJSON(_ text: String, sample: String, firstLine: String) -> Bool {
        if text.utf16.count <= jsonParseLimit {
            if (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil { return true }
        }
        let lines = nonEmptyLines(sample)
        if lines.count == 1 { return matches(jsonOpening, firstLine) }
        let jsonLines = lines.count { matches(jsonLine, $0) }
        return jsonLines * 10 >= lines.count * 6
    }

    private static let jsonOpening = regex(#"^\s*[\[{]\s*["\[{]"#)
    private static let jsonLine = regex(#"^\s*(?:[\[\]{}]+,?|"(?:[^"\\]|\\.)*"\s*(?::.*|,)?|-?\d[\d.eE+-]*,?|(?:true|false|null),?|\{\s*"(?:[^"\\]|\\.)*"\s*:.*|\[\s*["\[{].*)\s*$"#)
    private static let closingBrackets = regex(#"^\s*[)\]}]+[;,)]*\s*$"#)
    private static let markupFirstLine = regex(#"^<(?:!--.*|[A-Za-z][\w:.-]*(?:\s[^<>]*)?(?:/?>)?)\s*$"#)

    // A language whose lines match must also show its overall shape, so "Key: value" notes or a line starting with "Update" stay notes.
    private static let shapes: [ContentLanguage: NSRegularExpression] = [
        .yaml: regex(#"\A---[ \t]*$|^(?:-[ \t]+)?[\w.-]+:[ \t]*\n(?:[ \t]*(?:#.*)?\n)*[ \t]+\S|^-[ \t]+[\w.-]+:.*\n[ \t]+[\w.-]+:"#, [.anchorsMatchLines]),
        .sql: regex(#"^\s*(?:select\s+(?:distinct\s+)?(?:\*|[\w.]+\s*(?:,|\bfrom\b|\bas\b|$)|count\s*\()|insert\s+into\s+\w|update\s+[\w."`]+\s+set\b|delete\s+from\s+\w|create\s+(?:or\s+replace\s+)?(?:table|(?:unique\s+)?index|view|database|schema)\b|alter\s+table\s+\w|drop\s+(?:table|index|view|database)\b|with\s+\w+\s+as\s*\()"#, [.anchorsMatchLines, .caseInsensitive]),
    ]

    // When two languages match the same lines, the more specific one wins.
    private static func priority(_ language: ContentLanguage) -> Int {
        [.typescript, .swift, .python, .sql, .css, .javascript, .yaml, .shell].firstIndex(of: language) ?? 99
    }

    private static let htmlTags = regex(#"<(html|head|body|div|span|p|a|ul|ol|li|table|section|header|footer|main|nav|script|style|meta|link|title|h[1-6]|img|form|input|button|br)\b"#)

    private static let linePatterns: [(ContentLanguage, [NSRegularExpression])] = [
        (.markdown, [
            regex(#"^\s{0,3}#{1,6}\s+\S"#),
            regex(#"^\s*([-*+]|\d+[.)])\s+\S"#),
            regex(#"^\s*>\s?"#),
            regex(#"^\s*\|.*\|\s*$"#),
            regex(#"\*\*\S.*?\S\*\*|\[[^\]]+\]\([^)]+\)"#),
            // Prose: four or more words without code punctuation.
            regex(#"^(?=[^{};=<>$|`]*$)\s*\S+(\s+\S+){3,}\s*(?<!:)$"#),
        ]),
        (.python, [
            regex(#"^\s*def\s+\w+\s*\(.*\)\s*(->\s*[^:]+)?:\s*$"#),
            regex(#"^\s*class\s+\w+(\(.*\))?\s*:\s*$"#),
            regex(#"^\s*(from\s+[\w.]+\s+import\s+\w|import\s+[\w.]+(\s+as\s+\w+)?\s*$)"#),
            regex(#"^\s*(if|elif|else|for|while|with|try|except|finally)\b.*:\s*$"#),
            regex(#"^\s*print\(|\bself\.\w+|^\s*@\w+(\(.*\))?\s*$"#),
        ]),
        (.javascript, [
            regex(#"^\s*(export\s+)?(const|var)\s+[\w{\[]|^\s*let\s+\w+\s*=.*;\s*$"#),
            regex(#"^\s*(export\s+(default\s+)?)?(async\s+)?function\b"#),
            regex(#"\([^()]*\)\s*=>|=>\s*\{\s*$|\bconsole\.\w+\(|\brequire\(|\bdocument\.\w|\bwindow\.\w"#),
            regex(#"^\s*import\s+.*\s+from\s+['"]|^\s*export\s+"#),
            regex(#";\s*$"#),
            regex(#"^\s*(export\s+(default\s+)?)?(abstract\s+)?class\s+[\w$]+(\s+(extends|implements)\s+[\w$.<>, ]+)*\s*\{\s*$"#),
            regex(#"^\s*((static|async|get|set|public|private|protected|readonly|override)\s+)*(?!init\b)[a-z_$][\w$]*\s*\(.*\)\s*(:\s*[^{]+)?\{\s*$"#),
            regex(#"^\s*(switch\s*\(.*\)\s*\{|case\s+[^.\s].*:|default\s*:)\s*$|^\s*return\b.*[{(\[]\s*$"#),
        ]),
        (.typescript, [
            regex(#":\s*(string|number|boolean|any|void|unknown|never)(\[\])?\b"#),
            regex(#"^\s*(export\s+)?(interface|type|enum|namespace)\s+\w+"#),
            regex(#"^\s*(public|private|protected|readonly)\s+(?!((static|final|override|nonisolated|mutating)\s+)*(func|struct|enum|class|protocol|extension|actor|init|deinit|let|var|subscript|typealias)\b)\w+"#),
            // Typed parameters or a return type before the body; Swift declarations start with func and return with ->.
            regex(#"^(?!.*\bfunc\b).*\(\s*[\w$]+\??\s*:\s*[A-Z][\w$.<>\[\]|]*\s*[,)=]|\)\s*:\s*[\w$.<>\[\]| ]+\{\s*$"#),
        ]),
        (.swift, [
            regex(#"^\s*import\s+(Foundation|SwiftUI|UIKit|AppKit|Combine|Observation)\b"#),
            regex(#"^\s*((public|private|internal|fileprivate|open|static|final|override|@\w+)\s+)*(func|struct|enum|protocol|extension|actor)\s+\w+"#),
            regex(#"\b(let|var)\s+\w+\s*:\s*[A-Z\[]\w*|\bguard\s+.*\belse\b|\bif\s+let\s+\w+|^\s*(let|var)\s+\w+\s*=\s*[^;]*[^;\s]\s*$"#),
            // SwiftUI: return arrows (not Python's, which end in a colon), some View, view builders and modifiers.
            regex(#"->\s*[A-Z(\[][^:]*$|:\s*some\s+[A-Z]|^\s*[A-Z]\w*(\(.*\))?\s*\{(\s*[\w, ]+\s+in)?\s*$|^\s*\.[a-z]\w*\((?!.*=>)[^;]*\)\s*$"#),
        ]),
        (.css, [
            regex(#"^\s*([.#][\w-]+|(html|body|a|p|div|span|h[1-6]|ul|ol|li|img|table|button|input|\*)\b)[^(;]*\{\s*$"#),
            regex(#"^\s*[\w-]+\s*:\s*[^;{}]+;\s*$"#),
            regex(#"^\s*\}\s*$|^\s*@(media|import|font-face|keyframes|supports)\b"#),
        ]),
        (.yaml, [
            regex(#"^\s*(-\s+)?[\w.-]+:(\s+[^\s].*)?$"#),
            regex(#"^\s*-\s+\S"#),
            regex(#"^---\s*$"#),
        ]),
        (.sql, [
            regex(#"^\s*(select|insert\s+into|update|delete\s+from|create\s+(table|index|view|database)|alter\s+table|drop\s+(table|index|view)|with)\b"#, .caseInsensitive),
            regex(#"^\s*(from|where|join|left\s+join|inner\s+join|group\s+by|order\s+by|having|limit|values|set)\b"#, .caseInsensitive),
            regex(#";\s*$"#),
        ]),
        (.shell, [
            regex(#"^\s*(sudo\s+)?(echo|cd|export|source|alias|brew|apt(-get)?|npm|npx|yarn|pnpm|pip3?|git|curl|wget|ls|mkdir|rm|cp|mv|chmod|chown|cat|grep|sed|awk|docker|kubectl|ssh|scp|tar|swift|make|open|defaults|launchctl)\b"#),
            regex(#"^\s*(if\s+\[|then\b|fi\s*$|else\s*$|for\s+\w+\s+in\b|do\s*$|done\s*$|case\b.*\bin\s*$|esac\s*$)"#),
            regex(#"^\s*\w+=\S*\s*$|\$\{\w+|\$\(|"\$[A-Za-z_]\w*"|\s(&&|\|\|)\s|\s\|\s"#),
        ]),
    ]
}
