import AppKit
import HardydoNotesCore

final class LineNumberRuler: NSRulerView {
    private weak var textView: CodeTextView?
    private var observers: [NSObjectProtocol] = []
    private var lines: LineIndex

    var zoom: CGFloat {
        didSet {
            updateThickness()
            needsDisplay = true
        }
    }

    private func updateThickness() {
        let width = MarkdownTheme.gutterWidth(digits: String(lines.count).count, zoom: zoom)
        if ruleThickness != width { ruleThickness = width }
    }

    init(textView: CodeTextView, scrollView: NSScrollView, zoom: CGFloat) {
        self.textView = textView
        self.zoom = zoom
        lines = LineIndex(textView.string as NSString)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        updateThickness()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
        let center = NotificationCenter.default
        let redraw: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        observers = [
            // Posted while the storage processes the edit, the only moment its edited range is known.
            center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let storage = self.textView?.textStorage, storage.editedMask.contains(.editedCharacters) else { return }
                    self.lines.update(storage.string as NSString, edited: storage.editedRange, delta: storage.changeInLength)
                    self.needsDisplay = true
                    // Resizing the gutter retiles the scroll view, which must wait until the storage has finished editing.
                    DispatchQueue.main.async { [weak self] in self?.updateThickness() }
                }
            },
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main, using: redraw),
        ]
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override var isFlipped: Bool { true }

    override var requiredThickness: CGFloat { ruleThickness }

    // Views no longer clip to their bounds, so the dirty rect can reach into the text beside the gutter.
    override func draw(_ dirtyRect: NSRect) {
        let area = dirtyRect.intersection(bounds)
        (textView?.backgroundColor ?? .textBackgroundColor).setFill()
        area.fill()
        drawHashMarksAndLabels(in: area)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                let folds = textView.folds
        let caretLine = lines.lineNumber(at: min(textView.selectedRange().location, text.length))
        // A line break's own glyph reports a different position, so the baseline comes from the shared line metrics.
        let baseline = MarkdownTheme.baselineOffset(zoom)
        var index = text.lineRange(for: NSRange(location: characters.location, length: 0)).location
        while index < NSMaxRange(characters) {
            if let fold = folds.hidesLine(at: index) {
                index = NSMaxRange(fold) < text.length ? NSMaxRange(text.lineRange(for: NSRange(location: NSMaxRange(fold), length: 0))) : text.length
                continue
            }
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let line = lines.lineNumber(at: index)
            let glyph = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line, baseline: fragment.minY + baseline, in: textView, isCurrent: line == caretLine)
            let isFolded = folds.isFolded(lineStart: index)
            if isFolded || folds.regions[line - 1] != nil {
                drawChevron(folded: isFolded, center: fragment.minY + baseline - MarkdownTheme.baseFont(zoom).xHeight / 2, in: textView)
            }
            index = NSMaxRange(lineRange)
        }
        let extra = layoutManager.extraLineFragmentRect
        if NSMaxRange(characters) == text.length, !extra.isEmpty {
            let line = lines.count
            draw(line, baseline: extra.minY + baseline, in: textView, isCurrent: line == caretLine)
        }
    }

    private var chevrons: (zoom: CGFloat, open: NSImage?, folded: NSImage?)?

    // Symbol images are slow to build, and every scroll redraws the gutter, so they are made once per zoom.
    private func chevron(folded: Bool) -> NSImage? {
        if chevrons?.zoom != zoom {
            let configuration = NSImage.SymbolConfiguration(pointSize: 8.5 * zoom, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.labelColor.withAlphaComponent(0.7)]))
            chevrons = (
                zoom,
                NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Fold")?.withSymbolConfiguration(configuration),
                NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Unfold")?.withSymbolConfiguration(configuration)
            )
        }
        return folded ? chevrons?.folded : chevrons?.open
    }

    private func drawChevron(folded: Bool, center: CGFloat, in textView: NSTextView) {
        guard let image = chevron(folded: folded) else { return }
        let y = convert(NSPoint(x: 0, y: center + textView.textContainerOrigin.y), from: textView).y
        let column = MarkdownTheme.foldColumn * zoom
        let rect = NSRect(x: ruleThickness - column + (column - image.size.width) / 2, y: y - image.size.height / 2, width: image.size.width, height: image.size.height)
        image.draw(in: rect)
    }

    // A click anywhere on a line's gutter toggles the block starting there, like the chevron column in VS Code.
    override func mouseDown(with event: NSEvent) {
        guard let line = line(at: event) else { return }
        textView?.folds.toggle(line: line.number)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        guard let folds = textView?.folds, let line = line(at: event) else { return NSCursor.arrow.set() }
        let hasChevron = folds.isFolded(lineStart: line.start) || folds.regions[line.number] != nil
        (hasChevron ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    /// The 0-based line under the pointer and where it starts in the text.
    private func line(at event: NSEvent) -> (number: Int, start: Int)? {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let point = textView.convert(event.locationInWindow, from: nil)
        let origin = textView.textContainerOrigin
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: point.y - origin.y), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        guard point.y - origin.y <= fragment.maxY else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        let text = textView.string as NSString
        let start = text.lineRange(for: NSRange(location: min(index, text.length), length: 0)).location
        return (lines.lineNumber(at: start) - 1, start)
    }

    private var numberStyle: (zoom: CGFloat, normal: [NSAttributedString.Key: Any], current: [NSAttributedString.Key: Any])?

    private func draw(_ number: Int, baseline: CGFloat, in textView: NSTextView, isCurrent: Bool) {
        if numberStyle?.zoom != zoom {
            let font = MarkdownTheme.numberFont(zoom)
            numberStyle = (zoom, [.font: font, .foregroundColor: NSColor.tertiaryLabelColor], [.font: font, .foregroundColor: NSColor.controlAccentColor])
        }
        guard let numberStyle, let font = numberStyle.normal[.font] as? NSFont else { return }
        let label = String(number) as NSString
        let attributes = isCurrent ? numberStyle.current : numberStyle.normal
        let y = convert(NSPoint(x: 0, y: baseline + textView.textContainerOrigin.y), from: textView).y - font.ascender
        let width = label.size(withAttributes: attributes).width
        label.draw(at: NSPoint(x: ruleThickness - width - (MarkdownTheme.foldColumn + MarkdownTheme.numberGap) * zoom, y: y), withAttributes: attributes)
    }
}
