import Foundation

/// Lines `startLine + 1 ... endLine` hide when the region folds; lines count from 0.
public struct FoldRegion: Equatable, Sendable {
    public let startLine: Int
    public let endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

/*
 Ports VS Code's folding providers: the TypeScript/JSON/CSS syntax ranges for C-like languages, the Markdown
 language service for notes, and the indentation provider with `#region` markers for everything else.
 */
public enum CodeFolding {
    private static let maxRegions = 5_000
    private static let tabSize = 4

    public static func regions(in text: String, language: ContentLanguage, tokens: [SyntaxToken]? = nil) -> [FoldRegion] {
        let lines = Lines(text: text as NSString)
        let found: [FoldRegion] = switch language {
        case .json, .javascript, .typescript, .css, .swift:
            syntax(lines, language: language, tokens: tokens ?? SyntaxHighlighter.tokens(in: text, language: language))
        case .markdown:
            markdown(lines)
        default:
            indentation(lines, offSide: language == .python || language == .yaml)
        }
        return sanitize(found)
    }

    /*
     Moves fold regions past an edit of the old lines `first...last` that added `lineDelta` lines. Regions above
     stay, those below move, one enclosing the edit stretches, and any starting or ending on an edited line is
     dropped until the next full pass finds it again.
     */
    public static func shiftRegions(_ regions: [Int: Int], editedLines first: Int, through last: Int, lineDelta: Int) -> [Int: Int] {
        var shifted: [Int: Int] = [:]
        for (start, end) in regions {
            if end < first {
                shifted[start] = end
            } else if start > last {
                shifted[start + lineDelta] = end + lineDelta
            } else if start < first, end > last {
                shifted[start] = end + lineDelta
            }
        }
        return shifted
    }

    private static func isNewline(_ c: unichar) -> Bool {
        c == 10 || c == 13 || c == 0x85 || c == 0x2028 || c == 0x2029
    }

    struct Lines {
        let text: NSString
        private let lineIndex: LineIndex

        init(text: NSString) {
            self.text = text
            lineIndex = LineIndex(text)
        }

        var starts: [Int] { lineIndex.starts }
        var count: Int { lineIndex.count }

        func line(of location: Int) -> Int { lineIndex.line(at: location) }

        func content(_ line: Int) -> String {
            var end = line + 1 < starts.count ? starts[line + 1] : text.length
            while end > starts[line], CodeFolding.isNewline(text.character(at: end - 1)) { end -= 1 }
            return text.substring(with: NSRange(location: starts[line], length: end - starts[line]))
        }

        /// Columns of leading whitespace, or nil for a blank line.
        func indent(_ line: Int) -> Int? {
            let end = line + 1 < starts.count ? starts[line + 1] : text.length
            var column = 0
            var index = starts[line]
            while index < end {
                switch text.character(at: index) {
                case 32: column += 1
                case 9: column += tabSize - column % tabSize
                case let c where CodeFolding.isNewline(c): return nil
                default: return column
                }
                index += 1
            }
            return nil
        }

        func isBlank(_ line: Int) -> Bool { indent(line) == nil }
    }

    private static func match(_ regex: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// Mirrors VS Code's sanitizeRanges: one range per start line, and ranges that cross an enclosing one are dropped.
    private static func sanitize(_ regions: [FoldRegion]) -> [FoldRegion] {
        let sorted = regions
            .filter { $0.endLine > $0.startLine }
            .sorted { $0.startLine == $1.startLine ? $0.endLine > $1.endLine : $0.startLine < $1.startLine }
        var result: [FoldRegion] = []
        var stack: [FoldRegion] = []
        var top: FoldRegion?
        for entry in sorted {
            guard result.count < maxRegions else { break }
            guard let current = top else {
                top = entry
                result.append(entry)
                continue
            }
            guard entry.startLine > current.startLine else { continue }
            if entry.endLine <= current.endLine {
                stack.append(current)
            } else if entry.startLine > current.endLine {
                var enclosing: FoldRegion?
                repeat { enclosing = stack.popLast() } while enclosing.map { entry.startLine > $0.endLine } ?? false
                if let enclosing { stack.append(enclosing) }
            } else {
                continue
            }
            top = entry
            result.append(entry)
        }
        return result
    }

    private static let codeMarker = regex(#"^\s*(?://|/\*)\s*#?(end)?region\b"#)
    private static let htmlMarker = regex(#"^\s*<!--\s*#?(end)?region\b"#)
    private static let lineMarker = regex(#"^\s*(?://|/\*|#|--|<!--)\s*#?(end)?region\b"#)

    /// True for a region start, false for a region end.
    private static func marker(_ text: String, _ regex: NSRegularExpression) -> Bool? {
        match(regex, text).map { $0.range(at: 1).location == NSNotFound }
    }

    // A region hides everything through its end marker, as both the TypeScript and indentation providers do.
    private static func markerRegions(_ lines: Lines, _ regex: NSRegularExpression, skipping skip: (Int) -> Bool = { _ in false }) -> [FoldRegion] {
        var open: [Int] = []
        var result: [FoldRegion] = []
        for line in 0..<lines.count where !skip(line) {
            switch marker(lines.content(line), regex) {
            case true?: open.append(line)
            case false?: if let start = open.popLast() { result.append(FoldRegion(startLine: start, endLine: line)) }
            case nil: break
            }
        }
        return result
    }

    private static let switchKeyword = regex(#"\bswitch\b"#)
    private static let caseLabel = regex(#"^\s*(?:case\b|(?:@unknown\s+)?default\s*:)"#)
    private static let importStatement = regex(#"^import(?:\s|[{*"'])"#)

    /*
     Brackets fold from the opening line to the line before the closing one, which stays visible. TypeScript also
     folds case clauses, runs of line comments, multi-line comments and template strings, and groups of imports.
     */
    private static func syntax(_ lines: Lines, language: ContentLanguage, tokens: [SyntaxToken]) -> [FoldRegion] {
        let text = lines.text
        let isScript = language == .javascript || language == .typescript
        let hasSwitch = isScript || language == .swift
        let skipped = tokens.filter { $0.kind == .string || $0.kind == .comment || $0.kind == .property }.map(\.range).sorted { $0.location < $1.location }
        var result: [FoldRegion] = []
        var depth = [Int](repeating: 0, count: lines.count)
        var nextLine = 0
        var skip = 0
        var stack: [(char: unichar, line: Int, isSwitch: Bool)] = []
        let pairs: [unichar: unichar] = [125: 123, 93: 91, 41: 40]
        var characters = [unichar](repeating: 0, count: text.length)
        text.getCharacters(&characters, range: NSRange(location: 0, length: text.length))
        var index = 0
        while index < characters.count {
            while nextLine < lines.count, lines.starts[nextLine] <= index {
                depth[nextLine] = stack.count
                nextLine += 1
            }
            while skip < skipped.count, NSMaxRange(skipped[skip]) <= index { skip += 1 }
            if skip < skipped.count, skipped[skip].location <= index {
                index = NSMaxRange(skipped[skip])
                continue
            }
            let c = characters[index]
            if c == 123 || c == 91 || c == 40 {
                let line = nextLine - 1
                let isSwitch = hasSwitch && c == 123
                    && match(switchKeyword, text.substring(with: NSRange(location: lines.starts[line], length: index - lines.starts[line]))) != nil
                stack.append((c, line, isSwitch))
            } else if let open = pairs[c], let last = stack.last, last.char == open {
                stack.removeLast()
                let closeLine = nextLine - 1
                if closeLine - 1 > last.line {
                    result.append(FoldRegion(startLine: last.line, endLine: closeLine - 1))
                }
                if last.isSwitch {
                    result += caseClauses(lines, in: last.line..<closeLine, depth: stack.count + 1, depths: depth)
                }
            }
            index += 1
        }
        while nextLine < lines.count {
            depth[nextLine] = stack.count
            nextLine += 1
        }
        result += comments(lines, tokens: tokens, groupingLineComments: isScript || language == .swift)
        result += markerRegions(lines, codeMarker)
        if isScript {
            result += templateStrings(lines, tokens: tokens)
            result += importGroups(lines, depths: depth)
        }
        return result
    }

    // A clause runs from its label to its last statement, before the next label or the closing brace.
    private static func caseClauses(_ lines: Lines, in block: Range<Int>, depth: Int, depths: [Int]) -> [FoldRegion] {
        let labels = block.dropFirst().filter { depths[$0] == depth && match(caseLabel, lines.content($0)) != nil }
        var result: [FoldRegion] = []
        for (offset, label) in labels.enumerated() {
            var end = (offset + 1 < labels.count ? labels[offset + 1] : block.upperBound) - 1
            while end > label, lines.isBlank(end) { end -= 1 }
            result.append(FoldRegion(startLine: label, endLine: end))
        }
        return result
    }

    // Line comments only group when each stands alone on its line, with nothing but blank lines between them.
    private static func comments(_ lines: Lines, tokens: [SyntaxToken], groupingLineComments: Bool) -> [FoldRegion] {
        var result: [FoldRegion] = []
        var run: (first: Int, last: Int, count: Int)?
        func flush() {
            if let run, run.count >= 2 { result.append(FoldRegion(startLine: run.first, endLine: run.last)) }
            run = nil
        }
        for token in tokens.filter({ $0.kind == .comment && $0.range.length > 0 }).sorted(by: { $0.range.location < $1.range.location }) {
            let first = lines.line(of: token.range.location)
            let last = lines.line(of: NSMaxRange(token.range) - 1)
            if last > first {
                flush()
                result.append(FoldRegion(startLine: first, endLine: last))
                continue
            }
            let content = lines.content(first)
            let isAlone = lines.text.substring(with: token.range).hasPrefix("//")
                && content.prefix(token.range.location - lines.starts[first]).allSatisfy { $0 == " " || $0 == "\t" }
            guard groupingLineComments, isAlone, marker(content, codeMarker) == nil else {
                flush()
                continue
            }
            if let current = run, first > current.last, (current.last + 1..<first).allSatisfy(lines.isBlank) {
                run = (current.first, first, current.count + 1)
            } else {
                flush()
                run = (first, first, 1)
            }
        }
        flush()
        return result
    }

    // A closing backtick ends the fold one line early, like a closing bracket.
    private static func templateStrings(_ lines: Lines, tokens: [SyntaxToken]) -> [FoldRegion] {
        tokens.compactMap { token in
            guard token.kind == .string, token.range.length > 1 else { return nil }
            let value = lines.text.substring(with: token.range)
            guard value.hasPrefix("`") else { return nil }
            let first = lines.line(of: token.range.location)
            let last = lines.line(of: NSMaxRange(token.range) - 1)
            return FoldRegion(startLine: first, endLine: value.hasSuffix("`") ? max(last - 1, first) : last)
        }
    }

    // Consecutive top-level imports fold together; a statement ends where the next line starts outside any bracket.
    private static func importGroups(_ lines: Lines, depths: [Int]) -> [FoldRegion] {
        var result: [FoldRegion] = []
        var group: (first: Int, last: Int, count: Int)?
        func flush() {
            if let group, group.count >= 2 { result.append(FoldRegion(startLine: group.first, endLine: group.last)) }
            group = nil
        }
        var line = 0
        while line < lines.count {
            defer { line += 1 }
            guard depths[line] == 0, !lines.isBlank(line) else { continue }
            let content = lines.content(line).trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("//") || content.hasPrefix("/*") || content.hasPrefix("*") { continue }
            guard match(importStatement, content) != nil else {
                flush()
                continue
            }
            var end = line
            while end + 1 < lines.count, depths[end + 1] > 0 { end += 1 }
            group = group.map { ($0.first, end, $0.count + 1) } ?? (line, end, 1)
            line = end
        }
        flush()
        return result
    }

    /*
     VS Code's indentation provider, walking up from the last line. A block ends before the next line indented no
     deeper than its first; off-side languages (Python, YAML) leave the trailing blank lines outside the block.
     */
    private static func indentation(_ lines: Lines, offSide: Bool) -> [FoldRegion] {
        struct Previous {
            var indent: Int
            var endAbove: Int
            var line: Int
        }
        let markerIndent = -2
        var result: [FoldRegion] = []
        var previous = [Previous(indent: -1, endAbove: lines.count, line: lines.count)]
        for line in stride(from: lines.count - 1, through: 0, by: -1) {
            guard let indent = lines.indent(line) else {
                if offSide { previous[previous.count - 1].endAbove = line }
                continue
            }
            switch marker(lines.content(line), lineMarker) {
            case true?:
                if let open = previous.lastIndex(where: { $0.indent == markerIndent }) {
                    previous.removeSubrange((open + 1)...)
                    result.append(FoldRegion(startLine: line, endLine: previous[open].line))
                    previous[open] = Previous(indent: indent, endAbove: line, line: line)
                    continue
                }
            case false?:
                previous.append(Previous(indent: markerIndent, endAbove: line, line: line))
                continue
            case nil:
                break
            }
            if previous[previous.count - 1].indent > indent {
                repeat { previous.removeLast() } while previous[previous.count - 1].indent > indent
                let end = previous[previous.count - 1].endAbove - 1
                if end - line >= 1 { result.append(FoldRegion(startLine: line, endLine: end)) }
            }
            if previous[previous.count - 1].indent == indent {
                previous[previous.count - 1].endAbove = line
            } else {
                previous.append(Previous(indent: indent, endAbove: line, line: line))
            }
        }
        return result
    }

    private static let atxHeading = regex(#"^ {0,3}(#{1,6})(?:[ \t]|$)"#)
    private static let setextUnderline = regex(#"^ {0,3}(=+|-+)[ \t]*$"#)
    private static let fenceOpen = regex(#"^ {0,3}(`{3,}|~{3,})"#)
    private static let fenceClose = regex(#"^ {0,3}(`{3,}|~{3,})[ \t]*$"#)
    private static let listItem = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+|$)"#)
    private static let thematicBreak = regex(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let blockquote = regex(#"^ {0,3}>"#)
    private static let tableDelimiter = regex(#"^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#)
    private static let htmlBlock = regex(#"^ {0,3}<(?:!--|/?(?i:address|article|aside|blockquote|details|dialog|div|dl|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|li|main|nav|ol|p|pre|script|section|style|summary|table|tbody|td|tfoot|th|thead|tr|ul)(?:[ \t/>]|$))"#)

    private static func startsBlock(_ text: String) -> Bool {
        [listItem, atxHeading, fenceOpen, blockquote, thematicBreak, htmlBlock].contains { match($0, text) != nil }
    }

    struct MarkdownBlocks {
        var inFence: [Bool]
        var fences: [(start: Int, end: Int)] = []
        var tables: [(start: Int, end: Int)] = []
        var headings: [MarkdownHeading] = []
    }

    static func markdownBlocks(_ lines: Lines, _ contents: [String]) -> MarkdownBlocks {
        var blocks = MarkdownBlocks(inFence: [Bool](repeating: false, count: lines.count))
        var fenceStart: (line: Int, marker: String)?
        for line in contents.indices {
            if let start = fenceStart {
                blocks.inFence[line] = true
                if let found = match(fenceClose, contents[line]),
                   case let marker = (contents[line] as NSString).substring(with: found.range(at: 1)),
                   marker.first == start.marker.first, marker.count >= start.marker.count {
                    blocks.fences.append((start.line, line))
                    fenceStart = nil
                }
            } else if let found = match(fenceOpen, contents[line]) {
                blocks.inFence[line] = true
                fenceStart = (line, (contents[line] as NSString).substring(with: found.range(at: 1)))
            }
        }
        if let start = fenceStart { blocks.fences.append((start.line, lines.count - 1)) }

        let inFence = blocks.inFence
        var line = 0
        while line < lines.count {
            defer { line += 1 }
            let content = contents[line]
            guard !inFence[line], !lines.isBlank(line) else { continue }
            if let found = match(atxHeading, content) {
                let level = found.range(at: 1).length
                blocks.headings.append(MarkdownHeading(line: line, level: level, title: atxTitle(content, after: NSMaxRange(found.range(at: 1)))))
            } else if content.contains("|"), line + 1 < lines.count, !inFence[line + 1], match(tableDelimiter, contents[line + 1]) != nil {
                var end = line + 1
                while end + 1 < lines.count, !inFence[end + 1], !lines.isBlank(end + 1), !startsBlock(contents[end + 1]) { end += 1 }
                blocks.tables.append((line, end))
                line = end
            } else if line + 1 < lines.count, !inFence[line + 1], !startsBlock(content),
                      let found = match(setextUnderline, contents[line + 1]) {
                let level = (contents[line + 1] as NSString).substring(with: found.range(at: 1)).hasPrefix("=") ? 1 : 2
                blocks.headings.append(MarkdownHeading(line: line, level: level, title: content.trimmingCharacters(in: .whitespaces)))
                line += 1
            }
        }
        return blocks
    }

    private static let closingHashes = regex(#"[ \t]+#+[ \t]*$"#)

    private static func atxTitle(_ content: String, after markerEnd: Int) -> String {
        var title = (content as NSString).substring(from: markerEnd)
        if let found = match(closingHashes, title) {
            title = (title as NSString).substring(to: found.range.location)
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /*
     The Markdown language service folds headings to the next heading of the same or a higher level, and code fences,
     list items, tables, block quotes and HTML blocks over their whole extent. A single trailing blank line is dropped.
     */
    private static func markdown(_ lines: Lines) -> [FoldRegion] {
        var result: [FoldRegion] = []
        func add(_ start: Int, _ end: Int) {
            var end = end
            if end >= start + 1, lines.isBlank(end) { end -= 1 }
            result.append(FoldRegion(startLine: start, endLine: end))
        }
        let contents = (0..<lines.count).map(lines.content)
        let blocks = markdownBlocks(lines, contents)
        let inFence = blocks.inFence
        blocks.fences.forEach { add($0.start, $0.end) }
        var isTable = [Bool](repeating: false, count: lines.count)
        for table in blocks.tables {
            (table.start...table.end).forEach { isTable[$0] = true }
            add(table.start, table.end)
        }
        var open: [MarkdownHeading] = []
        for heading in blocks.headings {
            while let top = open.last, top.level >= heading.level {
                open.removeLast()
                add(top.line, heading.line - 1)
            }
            open.append(heading)
        }
        open.forEach { add($0.line, lines.count - 1) }

        for line in contents.indices where !inFence[line] && !isTable[line] {
            let content = contents[line]
            if let found = match(listItem, content), match(thematicBreak, content) == nil {
                add(line, listItemEnd(lines, contents, from: line, item: found))
            } else if match(blockquote, content) != nil, line == 0 || match(blockquote, contents[line - 1]) == nil {
                var end = line
                while end + 1 < lines.count, !inFence[end + 1], !lines.isBlank(end + 1),
                      match(blockquote, contents[end + 1]) != nil || !startsBlock(contents[end + 1]) { end += 1 }
                add(line, end)
            } else if match(htmlBlock, content) != nil, marker(content, htmlMarker) == nil {
                var end = line
                if content.contains("<!--") {
                    while end + 1 < lines.count, !contents[end].contains("-->") { end += 1 }
                } else {
                    while end + 1 < lines.count, !lines.isBlank(end + 1) { end += 1 }
                }
                add(line, end)
            }
        }
        result += markerRegions(lines, htmlMarker) { inFence[$0] }
        return result
    }

    // An item owns the lines indented to its content column, plus unindented lines that continue its paragraph.
    private static func listItemEnd(_ lines: Lines, _ contents: [String], from start: Int, item: NSTextCheckingResult) -> Int {
        let content = contents[start] as NSString
        let lead = content.substring(with: NSRange(location: 0, length: NSMaxRange(item.range(at: 2))))
        var column = lead.reduce(0) { $1 == "\t" ? $0 + tabSize - $0 % tabSize : $0 + 1 }
        let spacing = item.range(at: 3).length
        column += spacing == 0 || spacing > 4 ? 1 : spacing
        var last = start
        var previousBlank = false
        var line = start + 1
        while line < lines.count {
            defer { line += 1 }
            guard let indent = lines.indent(line) else {
                previousBlank = true
                continue
            }
            if indent >= column || (!previousBlank && !startsBlock(contents[line])) {
                last = line
                previousBlank = false
            } else {
                break
            }
        }
        return last
    }
}
