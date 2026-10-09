import AppKit
import HardydoNotesCore

/// VS Code's Dark+ colours.
enum SyntaxTheme {
    static let keys: [NSAttributedString.Key] = [.foregroundColor, .underlineStyle, .strikethroughStyle]

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static let keyword = color(0x569CD6)
    private static let string = color(0xCE9178)
    private static let number = color(0xB5CEA8)
    private static let comment = color(0x6A9955)
    private static let type = color(0x4EC9B0)
    private static let function = color(0xDCDCAA)
    private static let property = color(0x9CDCFE)
    private static let variable = color(0x9CDCFE)
    private static let tag = color(0x569CD6)
    private static let attribute = color(0x9CDCFE)
    private static let heading = color(0x569CD6)
    private static let link = color(0x3794FF)

    // Built once, since a colouring pass asks for them once per token.
    @MainActor private static let table = Dictionary(uniqueKeysWithValues: SyntaxKind.allCases.map { ($0, makeAttributes($0)) })

    @MainActor
    static func attributes(_ kind: SyntaxKind) -> [NSAttributedString.Key: Any] {
        table[kind] ?? [:]
    }

    private static func makeAttributes(_ kind: SyntaxKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .keyword, .literal: [.foregroundColor: keyword]
        case .string, .code: [.foregroundColor: string]
        case .number: [.foregroundColor: number]
        case .comment, .quote: [.foregroundColor: comment]
        case .type: [.foregroundColor: type]
        case .function: [.foregroundColor: function]
        case .property: [.foregroundColor: property]
        case .variable: [.foregroundColor: variable]
        case .tag: [.foregroundColor: tag]
        case .attribute: [.foregroundColor: attribute]
        case .punctuation: [.foregroundColor: NSColor.tertiaryLabelColor]
        case .heading, .listMarker, .emphasis: [.foregroundColor: heading]
        case .strike: [.foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .link: [.foregroundColor: link, .underlineStyle: NSUnderlineStyle.single.rawValue]
        }
    }
}

enum EditorTheme {
    static let foldColumn: CGFloat = 12
    static let lineHeight: CGFloat = 27
    private static let gutterLead: CGFloat = 10
    static let numberGap: CGFloat = 5

    static func numberFont(_ zoom: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: 12 * zoom, weight: .regular)
    }

    /// Room for the line numbers (at least two digits), then the fold chevrons.
    static func gutterWidth(digits: Int, zoom: CGFloat) -> CGFloat {
        let digit = ("0" as NSString).size(withAttributes: [.font: numberFont(zoom)]).width
        return ceil((gutterLead + numberGap + foldColumn) * zoom + CGFloat(max(2, digits)) * digit)
    }

    // Text sits 6pt after the gutter (CodeTextView pins the container to the left); the preview page's padding matches a two-digit gutter.
    @MainActor
    static func applyInsets(to textView: NSTextView, zoom: CGFloat) {
        textView.textContainerInset = NSSize(width: 10 * zoom, height: 8 * zoom)
        textView.textContainer?.lineFragmentPadding = 6 * zoom
    }

    static func baseFont(_ zoom: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: 13.5 * zoom, weight: .regular)
    }

    // Typing resets the attributes on every keystroke, so they are built once per zoom; only the main thread uses them.
    nonisolated(unsafe) private static var attributeCache: (zoom: CGFloat, attributes: [NSAttributedString.Key: Any])?

    static func baseAttributes(_ zoom: CGFloat) -> [NSAttributedString.Key: Any] {
        if let attributeCache, attributeCache.zoom == zoom { return attributeCache.attributes }
        let attributes = makeAttributes(zoom)
        attributeCache = (zoom, attributes)
        return attributes
    }

    private static func makeAttributes(_ zoom: CGFloat) -> [NSAttributedString.Key: Any] {
        // Half the extra height goes above the text and half below, so the text sits centred in its line as in VS Code.
        let font = baseFont(zoom)
        let natural = ceil(font.ascender - font.descender + font.leading)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (max(0, lineHeight * zoom - natural) / 2).rounded(.down)
        paragraph.minimumLineHeight = lineHeight * zoom - paragraph.lineSpacing
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }

    @MainActor private static var baselines: [CGFloat: CGFloat] = [:]

    /// Distance from a line's top to its baseline, the same for every line; measured once per zoom by laying out a sample.
    @MainActor
    static func baselineOffset(_ zoom: CGFloat) -> CGFloat {
        if let offset = baselines[zoom] { return offset }
        let storage = NSTextStorage(string: "Ag", attributes: baseAttributes(zoom))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(NSTextContainer(size: NSSize(width: 1_000, height: 1_000)))
        storage.addLayoutManager(layoutManager)
        let offset = layoutManager.location(forGlyphAt: 0).y
        baselines[zoom] = offset
        return offset
    }

    static func restyle(_ storage: NSTextStorage, zoom: CGFloat, range: NSRange? = nil) {
        storage.setAttributes(baseAttributes(zoom), range: range ?? NSRange(location: 0, length: storage.length))
    }
}
