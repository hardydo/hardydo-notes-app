import AppKit
import HardydoNotesCore

/*
 Folded lines stay in the text; their glyphs are generated as null so they take no space.
 The start line's line break becomes a fixed-width blank where the "⋯" badge is drawn.
 */
@MainActor
final class FoldState: NSObject, @preconcurrency NSLayoutManagerDelegate {
    weak var textView: NSTextView?
    var zoom: CGFloat = 1
    var onChange: () -> Void = {}
    private(set) var regions: [Int: Int] = [:]
    /// Every fold, sorted by location; a fold nested in another keeps its own state.
    private var folded: [NSRange] = [] {
        didSet { outer = Self.outermost(folded) }
    }
    /// The folds that decide what shows: sorted and never overlapping, so lookups can binary-search.
    private var outer: [NSRange] = []

    private var text: NSString { (textView?.string ?? "") as NSString }

    private static func outermost(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges where result.last.map({ NSMaxRange($0) <= range.location }) ?? true {
            result.append(range)
        }
        return result
    }

    private func firstOuter(endingAfter location: Int) -> Int {
        var low = 0
        var high = outer.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(outer[mid]) <= location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // Folds whose header line no longer starts a block (its bracket was deleted, say) open again.
    func setRegions(_ list: [FoldRegion]) {
        regions = Dictionary(list.map { ($0.startLine, $0.endLine) }, uniquingKeysWith: max)
        if !folded.isEmpty {
            let starts = CodeFolding.lineStarts(text)
            let headers = Set(regions.keys.filter { $0 < starts.count }.map { contentsEnd(ofLineAt: starts[$0]) })
            let stale = folded.filter { !headers.contains($0.location) }
            if let first = stale.first {
                set(folded.filter { headers.contains($0.location) }, touching: stale.reduce(first) { NSUnionRange($0, $1) })
            }
        }
        onChange()
    }

    private func contentsEnd(ofLineAt location: Int) -> Int {
        var end = 0
        text.getLineStart(nil, end: nil, contentsEnd: &end, for: NSRange(location: location, length: 0))
        return end
    }

    private func range(forLine line: Int, starts: [Int]) -> NSRange? {
        guard let endLine = regions[line], endLine < starts.count else { return nil }
        let start = contentsEnd(ofLineAt: starts[line])
        let end = contentsEnd(ofLineAt: starts[endLine])
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// The outer fold hiding this character, if any.
    func fold(containing index: Int) -> NSRange? {
        let found = firstOuter(endingAfter: index)
        return found < outer.count && outer[found].location <= index ? outer[found] : nil
    }

    /// The outer fold hiding this caret position; the position right after the header text stays visible.
    func hidesLine(at location: Int) -> NSRange? {
        let found = firstOuter(endingAfter: location - 1)
        return found < outer.count && outer[found].location < location ? outer[found] : nil
    }

    func isFolded(lineStart: Int) -> Bool {
        let end = contentsEnd(ofLineAt: lineStart)
        return folded.contains { $0.location == end }
    }

    func toggle(line: Int) {
        let starts = CodeFolding.lineStarts(text)
        guard line >= 0, line < starts.count else { return }
        let header = contentsEnd(ofLineAt: starts[line])
        let open = folded.filter { $0.location == header }
        if let first = open.first {
            set(folded.filter { $0.location != header }, touching: open.reduce(first) { NSUnionRange($0, $1) })
        } else if let range = range(forLine: line, starts: starts) {
            add([range])
        }
    }

    /// Folds the innermost block around the caret, as ⌥⌘[ does in VS Code.
    func foldAtCaret() {
        guard let caret = textView?.selectedRange().location else { return }
        let starts = CodeFolding.lineStarts(text)
        let line = CodeFolding.line(of: caret, in: starts)
        let candidates = regions.filter { $0.key <= line && line <= $0.value }
        guard let inner = candidates.max(by: { $0.key < $1.key }), let range = range(forLine: inner.key, starts: starts), !folded.contains(range) else { return }
        add([range])
    }

    func unfoldAtCaret() {
        guard let caret = textView?.selectedRange().location else { return }
        let lineEnd = contentsEnd(ofLineAt: caret)
        let hit = folded.filter { $0.location == lineEnd || ($0.location < caret && caret <= NSMaxRange($0)) }
        guard let first = hit.first else { return }
        set(folded.filter { !hit.contains($0) }, touching: hit.reduce(first) { NSUnionRange($0, $1) })
    }

    func foldAll() {
        let starts = CodeFolding.lineStarts(text)
        add(regions.keys.compactMap { range(forLine: $0, starts: starts) })
    }

    func unfoldAll() {
        guard !folded.isEmpty else { return }
        set([], touching: NSRange(location: 0, length: text.length))
    }

    /// Opens every fold hiding part of this range, so a find result or a revealed match shows.
    func unfold(intersecting range: NSRange) {
        let hit = folded.filter { NSIntersectionRange($0, NSRange(location: range.location, length: max(range.length, 1))).length > 0 || ($0.location < range.location && range.location <= NSMaxRange($0)) }
        guard let first = hit.first else { return }
        set(folded.filter { !hit.contains($0) }, touching: hit.reduce(first) { NSUnionRange($0, $1) })
    }

    func unfold(_ fold: NSRange) {
        set(folded.filter { $0 != fold }, touching: fold)
    }

    // New folds never leave the caret on hidden text, where the next keystroke would edit what cannot be seen.
    private func add(_ ranges: [NSRange]) {
        let new = ranges.filter { !folded.contains($0) }
        guard let first = new.first else { return }
        set((folded + new).sorted { $0.location < $1.location }, touching: new.reduce(first) { NSUnionRange($0, $1) })
        guard let textView else { return }
        let selection = textView.selectedRange()
        if let hiding = hidesLine(at: selection.location) ?? hidesLine(at: NSMaxRange(selection)) {
            textView.setSelectedRange(NSRange(location: hiding.location, length: 0))
        }
    }

    /*
     Edits before a fold move it and edits within its header line keep it, unless they add a line break there.
     Anything reaching into the hidden lines, or their last line break, opens it.
     */
    func textEdited(_ edited: NSRange, changeInLength delta: Int) {
        let inserted = text.substring(with: edited)
        if delta < 0 || inserted.contains(where: \.isNewline) { regions = [:] }
        guard !folded.isEmpty else { return }
        let old = NSRange(location: edited.location, length: edited.length - delta)
        var kept: [NSRange] = []
        var opened: [NSRange] = []
        for fold in folded {
            let before = old.length == 0 ? old.location <= fold.location : NSMaxRange(old) <= fold.location
            if before {
                let moved = NSRange(location: fold.location + delta, length: fold.length)
                let header = text.lineRange(for: NSRange(location: moved.location, length: 0)).location
                if NSMaxRange(edited) > header, inserted.contains(where: \.isNewline) {
                    opened.append(moved)
                } else {
                    kept.append(moved)
                }
            } else if old.location > NSMaxRange(fold) {
                kept.append(fold)
            } else {
                opened.append(fold)
            }
        }
        folded = kept
        guard let first = opened.first else { return }
        let touched = opened.reduce(first) { NSUnionRange($0, $1) }
        DispatchQueue.main.async { [weak self] in self?.invalidate(touched) }
    }

    /// Keeps the caret off hidden text: moving forward jumps past the fold, anything else lands after the header.
    func adjustSelection(from old: NSRange, to new: NSRange) -> NSRange {
        guard new.length == 0, let fold = hidesLine(at: new.location) else { return new }
        guard new.location < NSMaxRange(fold), new.location > old.location else { return NSRange(location: fold.location, length: 0) }
        let after = NSMaxRange(fold) < text.length ? NSMaxRange(text.lineRange(for: NSRange(location: NSMaxRange(fold), length: 0))) : text.length
        return NSRange(location: after, length: 0)
    }

    private func set(_ ranges: [NSRange], touching range: NSRange) {
        folded = ranges
        invalidate(range)
    }

    private func invalidate(_ range: NSRange) {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let length = text.length
        let start = min(range.location, length)
        let lineStart = text.lineRange(for: NSRange(location: start, length: 0)).location
        let touched = NSRange(location: lineStart, length: min(NSMaxRange(range) + 1, length) - lineStart)
        layoutManager.invalidateGlyphs(forCharacterRange: touched, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: touched, actualCharacterRange: nil)
        textView.needsDisplay = true
        onChange()
    }

    private var badgeFont: NSFont { MarkdownTheme.baseFont(zoom) }

    var badgeWidth: CGFloat {
        ("⋯" as NSString).size(withAttributes: [.font: badgeFont]).width + badgeFont.pointSize
    }

    private func badgeRect(for fold: NSRange) -> NSRect? {
        guard let textView, let layoutManager = textView.layoutManager, fold.location < text.length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: fold.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = layoutManager.location(forGlyphAt: glyph)
        let font = badgeFont
        let origin = textView.textContainerOrigin
        let top = line.minY + MarkdownTheme.baselineOffset(zoom) - ceil(font.ascender) - 1
        return NSRect(x: line.minX + position.x + origin.x + 2, y: top + origin.y, width: badgeWidth - 4, height: ceil(font.ascender - font.descender) + 2)
    }

    /// The outer folds whose header sits in this part of the view.
    private func outerFolds(in rect: NSRect) -> ArraySlice<NSRange> {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer, !outer.isEmpty else { return [] }
        let origin = textView.textContainerOrigin
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = firstOuter(endingAfter: characters.location - 1)
        var last = first
        while last < outer.count, outer[last].location <= NSMaxRange(characters) { last += 1 }
        return outer[first..<last]
    }

    func drawBadges(in dirtyRect: NSRect) {
        for fold in outerFolds(in: dirtyRect) {
            guard let rect = badgeRect(for: fold), rect.intersects(dirtyRect) else { continue }
            NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let label = NSAttributedString(string: "⋯", attributes: [.font: badgeFont, .foregroundColor: NSColor.secondaryLabelColor])
            let size = label.size()
            label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    func fold(atBadge point: NSPoint) -> NSRange? {
        outerFolds(in: NSRect(x: point.x, y: point.y, width: 1, height: 1)).first { badgeRect(for: $0)?.contains(point) == true }
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard !outer.isEmpty, glyphRange.length > 0 else { return 0 }
        var cursor = firstOuter(endingAfter: characterIndexes[0])
        guard cursor < outer.count, outer[cursor].location <= characterIndexes[glyphRange.length - 1] else { return 0 }
        var changed = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        for index in 0..<glyphRange.length {
            let character = characterIndexes[index]
            while cursor < outer.count, NSMaxRange(outer[cursor]) <= character { cursor += 1 }
            guard cursor < outer.count, outer[cursor].location <= character else { continue }
            changed[index] = character == outer[cursor].location ? .controlCharacter : .null
        }
        layoutManager.setGlyphs(glyphs, properties: changed, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let fold = fold(containing: charIndex) else { return action }
        return charIndex == fold.location ? .whitespace : .zeroAdvancement
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: glyphPosition.x, y: 0, width: badgeWidth, height: 0)
    }
}
