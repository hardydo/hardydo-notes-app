import Foundation

/// VS Code's line commands, as edits on the editor's text.
public enum LineEditing {
    public enum Direction: Sendable {
        case up, down
    }

    /// The whole lines a selection touches, with the last line break; a selection ending at a line start leaves that line out.
    public static func lineBlock(_ text: NSString, _ selection: NSRange) -> NSRange {
        var end = NSMaxRange(selection)
        if selection.length > 0, end > selection.location, end <= text.length, isLineStart(text, end) { end -= 1 }
        let first = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let last = text.lineRange(for: NSRange(location: min(end, text.length), length: 0))
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    public static func moveLines(_ text: String, selection: NSRange, _ direction: Direction) -> TextEdit? {
        let ns = text as NSString
        let block = lineBlock(ns, selection)
        let neighbor: NSRange
        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            neighbor = ns.lineRange(for: NSRange(location: block.location - 1, length: 0))
        case .down:
            guard NSMaxRange(block) < ns.length else { return nil }
            neighbor = ns.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
        }
        let region = NSUnionRange(block, neighbor)
        // The lines trade places while each line break stays where it was, so the file keeps its own endings.
        let parts = lines(ns, region)
        let contents = parts.map(\.content)
        let swapped = direction == .down ? [contents[contents.count - 1]] + contents.dropLast() : Array(contents.dropFirst()) + [contents[0]]
        let moved = direction == .down ? parts[parts.count - 1].content : parts[0].content
        let shift = ((moved as NSString).length + (parts[0].lineBreak as NSString).length) * (direction == .down ? 1 : -1)
        return TextEdit(
            range: region,
            replacement: zip(swapped, parts).map { $0 + $1.lineBreak }.joined(),
            selection: NSRange(location: selection.location + shift, length: selection.length)
        )
    }

    /// The copy goes below and takes the selection when copying down; copying up leaves the selection on the upper copy.
    public static func copyLines(_ text: String, selection: NSRange, _ direction: Direction) -> TextEdit {
        let ns = text as NSString
        let block = lineBlock(ns, selection)
        let copy = ns.substring(with: block)
        // The last line has no break of its own, so the copy borrows the one before it.
        let replacement = endsWithBreak(ns, block) ? copy : lineBreak(before: block.location, in: ns) + copy
        let shift = direction == .down ? (replacement as NSString).length : 0
        return TextEdit(range: NSRange(location: NSMaxRange(block), length: 0), replacement: replacement,
                        selection: NSRange(location: selection.location + shift, length: selection.length))
    }

    public static func deleteLines(_ text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let block = lineBlock(ns, selection)
        // The last line has no break of its own, so the one before it goes instead.
        if !endsWithBreak(ns, block), block.location > 0 {
            let previous = ns.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let start = contentEnd(ns, previous)
            return TextEdit(range: NSRange(location: start, length: NSMaxRange(block) - start), replacement: "",
                            selection: NSRange(location: previous.location, length: 0))
        }
        return TextEdit(range: block, replacement: "", selection: NSRange(location: block.location, length: 0))
    }

    public static func insertLine(_ text: String, selection: NSRange, _ direction: Direction) -> TextEdit {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let indent = indentation(ns, line)
        switch direction {
        case .down:
            let end = contentEnd(ns, ns.lineRange(for: NSRange(location: NSMaxRange(selection), length: 0)))
            return TextEdit(range: NSRange(location: end, length: 0), replacement: "\n" + indent,
                            selection: NSRange(location: end + 1 + (indent as NSString).length, length: 0))
        case .up:
            return TextEdit(range: NSRange(location: line.location, length: 0), replacement: indent + "\n",
                            selection: NSRange(location: line.location + (indent as NSString).length, length: 0))
        }
    }

    /// Like VS Code, a new line starts at the indentation of the line it was split from; nil when that line has none.
    public static func newlineKeepingIndent(_ text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let indent = indentation(ns, NSRange(location: lineStart, length: selection.location - lineStart))
        guard !indent.isEmpty else { return nil }
        let replacement = "\n" + indent
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    /// A tab when the text already indents with tabs, otherwise four spaces.
    public static func indentUnit(for text: String) -> String {
        var unit = "    "
        text.enumerateLines { line, stop in
            guard let first = line.first, first == "\t" || first == " " else { return }
            if first == "\t" { unit = "\t" }
            stop = true
        }
        return unit
    }

    public static func indent(_ text: String, selection: NSRange, unit: String) -> TextEdit {
        reindent(text, selection: selection) { _ in unit }
    }

    public static func outdent(_ text: String, selection: NSRange, unit: String) -> TextEdit {
        let width = (unit as NSString).length
        return reindent(text, selection: selection) { line in
            if line.hasPrefix("\t") { return "-\t" }
            return "-" + String(line.prefix(width).prefix { $0 == " " })
        }
    }

    /// Comments out the lines, or uncomments them when every line with text is already commented.
    public static func toggleComment(_ text: String, selection: NSRange, language: ContentLanguage) -> TextEdit? {
        let ns = text as NSString
        let block = lineBlock(ns, selection)
        let body = NSRange(location: block.location, length: contentEnd(ns, block) - block.location)
        if let token = language.lineComment {
            return toggleLineComment(ns, selection: selection, block: body, token: token)
        }
        if let (open, close) = language.blockComment {
            return toggleBlockComment(ns, selection: selection, block: body, open: open, close: close)
        }
        return nil
    }

    /// The selected lines; when whole lines are already selected, the next line joins them.
    public static func selectLine(_ text: String, selection: NSRange) -> NSRange {
        let ns = text as NSString
        let block = lineBlock(ns, selection)
        guard block == selection, NSMaxRange(block) < ns.length else { return block }
        return NSUnionRange(block, ns.lineRange(for: NSRange(location: NSMaxRange(block), length: 0)))
    }

    /// Where a 1-based line number starts, clamped to the text.
    public static func location(ofLine line: Int, in text: String) -> Int {
        let starts = LineIndex(text as NSString).starts
        return starts[min(max(line, 1), starts.count) - 1]
    }

    private static func toggleLineComment(_ ns: NSString, selection: NSRange, block: NSRange, token: String) -> TextEdit {
        let parts = lines(ns, block)
        let contents = parts.map(\.content)
        let filled = contents.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let isCommented = !filled.isEmpty && filled.allSatisfy { $0.drop { $0 == " " || $0 == "\t" }.hasPrefix(token) }
        let column = filled.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        var delta = 0
        var firstDelta = 0
        let changed = contents.enumerated().map { offset, line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let result: String
            if isCommented {
                let lead = line.prefix { $0 == " " || $0 == "\t" }
                var rest = line.dropFirst(lead.count).dropFirst(token.count)
                if rest.first == " " { rest = rest.dropFirst() }
                result = String(lead) + rest
            } else {
                let index = line.index(line.startIndex, offsetBy: column)
                result = String(line[..<index]) + token + " " + line[index...]
            }
            let change = (result as NSString).length - (line as NSString).length
            if offset == 0 { firstDelta = change }
            delta += change
            return result
        }
        let replacement = zip(changed, parts).map { $0 + $1.lineBreak }.joined()
        let start = max(block.location, selection.location + firstDelta)
        let end = selection.length == 0 ? start : NSMaxRange(selection) + delta
        return TextEdit(range: block, replacement: replacement, selection: NSRange(location: start, length: max(0, end - start)))
    }

    private static func toggleBlockComment(_ ns: NSString, selection: NSRange, block: NSRange, open: String, close: String) -> TextEdit {
        let content = ns.substring(with: block)
        let lead = String(content.prefix { $0 == " " || $0 == "\t" })
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(open), trimmed.hasSuffix(close), trimmed.count >= open.count + close.count {
            var inner = trimmed.dropFirst(open.count).dropLast(close.count)
            if inner.first == " " { inner = inner.dropFirst() }
            if inner.last == " " { inner = inner.dropLast() }
            let replacement = lead + inner
            return TextEdit(range: block, replacement: replacement,
                            selection: NSRange(location: block.location, length: (replacement as NSString).length))
        }
        let replacement = lead + open + " " + content.dropFirst(lead.count) + " " + close
        return TextEdit(range: block, replacement: replacement,
                        selection: NSRange(location: block.location, length: (replacement as NSString).length))
    }

    /// Applies `change` to each line's start: a string starting with "-" removes that many characters, anything else is inserted.
    private static func reindent(_ text: String, selection: NSRange, change: (String) -> String) -> TextEdit {
        let ns = text as NSString
        let block = lineBlock(ns, selection)
        let body = NSRange(location: block.location, length: contentEnd(ns, block) - block.location)
        var deltas: [Int] = []
        let parts = lines(ns, body)
        let changed = parts.map(\.content).map { line -> String in
            let edit = change(line)
            if edit.hasPrefix("-") {
                let count = edit.count - 1
                deltas.append(-(String(line.prefix(count)) as NSString).length)
                return String(line.dropFirst(count))
            }
            guard !line.isEmpty || selection.length == 0 else {
                deltas.append(0)
                return line
            }
            deltas.append((edit as NSString).length)
            return edit + line
        }
        let replacement = zip(changed, parts).map { $0 + $1.lineBreak }.joined()
        let total = deltas.reduce(0, +)
        let start = max(body.location, selection.location + (deltas.first ?? 0))
        let end = selection.length == 0 ? start : NSMaxRange(selection) + total
        return TextEdit(range: body, replacement: replacement, selection: NSRange(location: start, length: max(0, end - start)))
    }

    /// The lines of `range`, each apart from its line break, split where the gutter splits them.
    private static func lines(_ ns: NSString, _ range: NSRange) -> [(content: String, lineBreak: String)] {
        let part = ns.substring(with: range) as NSString
        let index = LineIndex(part)
        var result = (0..<index.count).map { line -> (content: String, lineBreak: String) in
            let start = index.starts[line]
            let end = line + 1 < index.count ? index.starts[line + 1] : part.length
            let contentEnd = index.contentsEnd(ofLine: line, in: part)
            return (part.substring(with: NSRange(location: start, length: contentEnd - start)),
                    part.substring(with: NSRange(location: contentEnd, length: end - contentEnd)))
        }
        if result.count > 1, result[result.count - 1] == ("", "") { result.removeLast() }
        return result
    }

    private static func endsWithBreak(_ ns: NSString, _ range: NSRange) -> Bool {
        range.length > 0 && isNewline(ns.character(at: NSMaxRange(range) - 1))
    }

    private static func lineBreak(before location: Int, in ns: NSString) -> String {
        guard location > 0 else { return "\n" }
        let previous = ns.lineRange(for: NSRange(location: location - 1, length: 0))
        let end = contentEnd(ns, previous)
        return end < NSMaxRange(previous) ? ns.substring(with: NSRange(location: end, length: NSMaxRange(previous) - end)) : "\n"
    }

    private static func isNewline(_ c: unichar) -> Bool {
        c == 10 || c == 13 || c == 0x85 || c == 0x2028 || c == 0x2029
    }

    private static func indentation(_ ns: NSString, _ line: NSRange) -> String {
        var end = line.location
        while end < NSMaxRange(line), [9, 32].contains(ns.character(at: end)) { end += 1 }
        return ns.substring(with: NSRange(location: line.location, length: end - line.location))
    }

    private static func contentEnd(_ ns: NSString, _ line: NSRange) -> Int {
        var end = NSMaxRange(line)
        while end > line.location, isNewline(ns.character(at: end - 1)) { end -= 1 }
        return end
    }

    private static func isLineStart(_ ns: NSString, _ location: Int) -> Bool {
        guard location > 0 else { return true }
        let previous = ns.character(at: location - 1)
        return isNewline(previous) && !(previous == 13 && location < ns.length && ns.character(at: location) == 10)
    }
}

extension ContentLanguage {
    public var lineComment: String? {
        switch self {
        case .javascript, .typescript, .swift: "//"
        case .python, .yaml, .shell: "#"
        case .sql: "--"
        case .markdown, .plainText, .json, .html, .xml, .css: nil
        }
    }

    public var blockComment: (String, String)? {
        switch self {
        case .css: ("/*", "*/")
        case .markdown, .html, .xml: ("<!--", "-->")
        default: nil
        }
    }
}
