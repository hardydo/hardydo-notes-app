import AppKit
import HardydoNotesCore

final class LineNumberRuler: NSRulerView {
    private weak var textView: CodeTextView?
    private var observers: [NSObjectProtocol] = []
    private var caretLine = 0

    var zoom: CGFloat {
        didSet {
            updateThickness()
            needsDisplay = true
        }
    }

    private func updateThickness() {
        let width = EditorTheme.gutterWidth(digits: String(textView?.lines.count ?? 1).count, zoom: zoom)
        if ruleThickness != width { ruleThickness = width }
    }

    init(textView: CodeTextView, scrollView: NSScrollView, zoom: CGFloat) {
        self.textView = textView
        self.zoom = zoom
        caretLine = textView.caretLine
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        updateThickness()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.textView?.textStorage?.editedMask.contains(.editedCharacters) == true else { return }
                    self.needsDisplay = true
                    // Resizing the gutter retiles the scroll view, which must wait until the storage has finished editing.
                    DispatchQueue.main.async { [weak self] in self?.updateThickness() }
                }
            },
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.caretMoved() }
            },
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

    // Only the old and new caret lines change colour; an edit redraws the whole gutter anyway.
    private func caretMoved() {
        guard let textView else { return }
        let line = textView.caretLine
        guard line != caretLine else { return }
        for changed in [caretLine, line] {
            if let rect = rect(ofLine: changed, in: textView) { setNeedsDisplay(rect) }
        }
        caretLine = line
    }

    private func rect(ofLine line: Int, in textView: CodeTextView) -> NSRect? {
        guard let layoutManager = textView.layoutManager, line < textView.lines.count else { return nil }
        let start = textView.lines.starts[line]
        let fragment = start < (textView.textStorage?.length ?? 0)
            ? layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            : layoutManager.extraLineFragmentRect
        let top = convert(NSPoint(x: 0, y: fragment.minY + textView.textContainerOrigin.y), from: textView).y
        return NSRect(x: 0, y: top, width: bounds.width, height: fragment.height)
    }

    override var requiredThickness: CGFloat { ruleThickness }

    // Views no longer clip to their bounds, so the dirty rect can reach into the text beside the gutter.
    override func draw(_ dirtyRect: NSRect) {
        let area = dirtyRect.intersection(bounds)
        (textView?.backgroundColor ?? .textBackgroundColor).setFill()
        area.fill()
        drawHashMarksAndLabels(in: area)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let text = textView.textStorage?.mutableString else { return }
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let folds = textView.folds
        let lines = textView.lines
        caretLine = textView.caretLine
        // A line break's own glyph reports a different position, so the baseline comes from the shared line metrics.
        let baseline = EditorTheme.baselineOffset(zoom)
        var line = lines.line(at: characters.location)
        while line < lines.count, lines.starts[line] < NSMaxRange(characters) {
            let start = lines.starts[line]
            if let fold = folds.hidesLine(at: start) {
                line = lines.line(at: NSMaxRange(fold)) + 1
                continue
            }
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            draw(line + 1, baseline: fragment.minY + baseline, in: textView, isCurrent: line == caretLine)
            let isFolded = folds.isFolded(line: line)
            if isFolded || folds.regions[line] != nil {
                drawChevron(folded: isFolded, center: fragment.minY + baseline - EditorTheme.baseFont(zoom).xHeight / 2, in: textView)
            }
            line += 1
        }
        let extra = layoutManager.extraLineFragmentRect
        if NSMaxRange(characters) == text.length, !extra.isEmpty {
            draw(lines.count, baseline: extra.minY + baseline, in: textView, isCurrent: lines.count - 1 == caretLine)
        }
    }

    private var chevrons: (zoom: CGFloat, open: NSImage?, folded: NSImage?)?

    // Symbol images are slow to build, and every scroll redraws the gutter, so they are made once per zoom.
    private func chevron(folded: Bool) -> NSImage? {
        if chevrons?.zoom != zoom {
            let configuration = NSImage.SymbolConfiguration(pointSize: 7.5 * zoom, weight: .bold)
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
        let column = EditorTheme.foldColumn * zoom
        let rect = NSRect(x: ruleThickness - column + (column - image.size.width) / 2, y: y - image.size.height / 2, width: image.size.width, height: image.size.height)
        image.draw(in: rect)
    }

    // A click anywhere on a line's gutter toggles the block starting there, like the chevron column in VS Code.
    override func mouseDown(with event: NSEvent) {
        guard let line = line(at: event) else { return }
        textView?.folds.toggle(line: line)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        guard let folds = textView?.folds, let line = line(at: event) else { return NSCursor.arrow.set() }
        let hasChevron = folds.isFolded(line: line) || folds.regions[line] != nil
        (hasChevron ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    /// The 0-based line under the pointer.
    private func line(at event: NSEvent) -> Int? {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let point = textView.convert(event.locationInWindow, from: nil)
        let origin = textView.textContainerOrigin
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: point.y - origin.y), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        guard point.y - origin.y <= fragment.maxY else { return nil }
        return textView.lines.line(at: layoutManager.characterIndexForGlyph(at: glyph))
    }

    private var numberStyle: (zoom: CGFloat, digit: CGFloat, normal: [NSAttributedString.Key: Any], current: [NSAttributedString.Key: Any])?

    private func draw(_ number: Int, baseline: CGFloat, in textView: NSTextView, isCurrent: Bool) {
        if numberStyle?.zoom != zoom {
            let font = EditorTheme.numberFont(zoom)
            let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
            numberStyle = (zoom, digit, [.font: font, .foregroundColor: NSColor.tertiaryLabelColor], [.font: font, .foregroundColor: NSColor.controlAccentColor])
        }
        guard let numberStyle, let font = numberStyle.normal[.font] as? NSFont else { return }
        let label = String(number) as NSString
        let attributes = isCurrent ? numberStyle.current : numberStyle.normal
        let y = convert(NSPoint(x: 0, y: baseline + textView.textContainerOrigin.y), from: textView).y - font.ascender
        // The digits are monospaced, so the width needs no text measuring.
        let width = numberStyle.digit * CGFloat(label.length)
        label.draw(at: NSPoint(x: ruleThickness - width - (EditorTheme.foldColumn + EditorTheme.numberGap) * zoom, y: y), withAttributes: attributes)
    }
}
