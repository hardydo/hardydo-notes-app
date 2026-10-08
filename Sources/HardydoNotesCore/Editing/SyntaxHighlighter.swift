import Foundation

public enum SyntaxKind: Equatable, Sendable {
    case keyword
    case string
    case number
    case literal
    case comment
    case type
    case function
    case property
    case variable
    case tag
    case attribute
    case punctuation
    case heading
    case emphasis
    case strike
    case code
    case link
    case quote
    case listMarker
}

public struct SyntaxToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: SyntaxKind

    public init(_ range: NSRange, _ kind: SyntaxKind) {
        self.range = range
        self.kind = kind
    }
}

/// Colours text the way a code editor would. Later tokens win where they overlap.
public enum SyntaxHighlighter {
    public static func tokens(in text: String, language: ContentLanguage) -> [SyntaxToken] {
        tokens(in: text, range: NSRange(location: 0, length: (text as NSString).length), language: language)
    }

    static func tokens(in text: String, range: NSRange, language: ContentLanguage) -> [SyntaxToken] {
        switch language {
        case .markdown: markdown(text)
        case .plainText: []
        case .html, .xml: markup(text, range: range, language: language)
        case .yaml: (lexers[.yaml]?.tokens(in: text, range: range) ?? []) + yamlKeys(text, range: range)
        default: lexers[language]?.tokens(in: text, range: range) ?? []
        }
    }

    private static func markdown(_ text: String) -> [SyntaxToken] {
        let ns = text as NSString
        var fenced: [NSRange: (body: NSRange, language: ContentLanguage)] = [:]
        for match in fence.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let info = match.range(at: 1).location == NSNotFound ? "" : ns.substring(with: match.range(at: 1))
            if let language = ContentLanguage.fenceLanguage(info), language != .markdown, language != .plainText {
                fenced[match.range] = (match.range(at: 2), language)
            }
        }
        var result: [SyntaxToken] = []
        for span in MarkdownStyler.spans(in: text) {
            if span.style == .codeBlock, let block = fenced[span.range] {
                result += tokens(in: text, range: block.body, language: block.language)
                continue
            }
            result.append(SyntaxToken(span.range, kind(of: span.style)))
        }
        return result
    }

    private static func kind(of style: MarkdownStyle) -> SyntaxKind {
        switch style {
        case .heading: .heading
        case .bold, .italic: .emphasis
        case .strikethrough, .taskDone: .strike
        case .inlineCode, .codeBlock: .code
        case .quote: .quote
        case .listMarker: .listMarker
        case .link: .link
        case .syntax: .punctuation
        }
    }

    private static let fence = regex(#"^```[ \t]*([^\s`]*)[^\n]*\n([\s\S]*?)(?:^```[ \t]*$|\z)"#, [.anchorsMatchLines])

    // Keys are found per line apart from the lexer, since a look-behind for the indentation would run at every character.
    private static let yamlKey = regex(#"^[ \t]*(?:-[ \t]+)?([^\s#:\-"'][^:\n]*?):(?=[ \t]|$)"#, [.anchorsMatchLines])

    private static func yamlKeys(_ text: String, range: NSRange) -> [SyntaxToken] {
        yamlKey.matches(in: text, options: [.withTransparentBounds], range: range).map { SyntaxToken($0.range(at: 1), .property) }
    }

    private static let markupBlock = regex(#"<!--[\s\S]*?(?:-->|\z)|<!\[CDATA\[[\s\S]*?(?:\]\]>|\z)|<[!?][^>]*>?|</?[A-Za-z][^>]*>?|&(?:#\d+|#x[0-9a-fA-F]+|\w+);"#)
    private static let tagName = regex(#"^</?([\w:.-]+)"#)
    private static let tagInside = Lexer([
        (#""[^"]*"?|'[^']*'?"#, .string),
        (#"[\w:.@-]+"#, .attribute),
        (#"/?>|="#, .punctuation),
    ])
    private static let embedded = regex(#"^<(script|style)\b"#, [.caseInsensitive])

    private static func markup(_ text: String, range: NSRange, language: ContentLanguage) -> [SyntaxToken] {
        let ns = text as NSString
        var result: [SyntaxToken] = []
        var embeddedStart: (location: Int, language: ContentLanguage, closing: String)?
        for match in markupBlock.matches(in: text, range: range) {
            let block = ns.substring(with: match.range)
            if let open = embeddedStart {
                guard block.lowercased().hasPrefix(open.closing) else { continue }
                result += tokens(in: text, range: NSRange(location: open.location, length: match.range.location - open.location), language: open.language)
                embeddedStart = nil
            }
            if block.hasPrefix("<!--") {
                result.append(SyntaxToken(match.range, .comment))
            } else if block.hasPrefix("<![CDATA[") {
                result.append(SyntaxToken(match.range, .string))
            } else if block.hasPrefix("<!") || block.hasPrefix("<?") {
                result.append(SyntaxToken(match.range, .keyword))
            } else if block.hasPrefix("&") {
                result.append(SyntaxToken(match.range, .literal))
            } else {
                result += tag(match.range, in: text)
                if language == .html, !block.hasPrefix("</"), !block.hasSuffix("/>"),
                   let name = embedded.firstMatch(in: block, range: NSRange(location: 0, length: (block as NSString).length)) {
                    let tagName = (block as NSString).substring(with: name.range(at: 1)).lowercased()
                    embeddedStart = (NSMaxRange(match.range), tagName == "style" ? .css : .javascript, "</" + tagName)
                }
            }
        }
        if let open = embeddedStart {
            result += tokens(in: text, range: NSRange(location: open.location, length: NSMaxRange(range) - open.location), language: open.language)
        }
        return result
    }

    private static func tag(_ range: NSRange, in text: String) -> [SyntaxToken] {
        let ns = text as NSString
        let tag = ns.substring(with: range)
        guard let name = tagName.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return [] }
        let nameRange = name.range(at: 1)
        var result = [
            SyntaxToken(NSRange(location: range.location, length: nameRange.location), .punctuation),
            SyntaxToken(NSRange(location: range.location + nameRange.location, length: nameRange.length), .tag),
        ]
        let rest = NSRange(location: range.location + NSMaxRange(nameRange), length: range.length - NSMaxRange(nameRange))
        result += tagInside.tokens(in: text, range: rest)
        return result
    }

    fileprivate static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let dq = #""[^"\\\n]*+(?:\\.[^"\\\n]*+)*+"?"#
    private static let sq = #"'[^'\\\n]*+(?:\\.[^'\\\n]*+)*+'?"#
    private static let slashComments = #"//.*|/\*[\s\S]*?(?:\*/|\z)"#
    private static let number = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#
    private static let call = #"\b[a-zA-Z_$][\w$]*(?=\s*\()"#
    private static let capitalized = #"\b[A-Z][A-Za-z0-9_]*\b"#

    private static func words(_ list: String) -> String {
        #"\b(?:"# + list.split(separator: " ").joined(separator: "|") + #")\b"#
    }

    private static let jsKeywords = "break case catch class const continue debugger default delete do else export extends finally for from function if import in instanceof let new of return static super switch this throw try typeof var void while with yield async await get set"
    private static let tsKeywords = jsKeywords + " interface type enum implements namespace declare abstract public private protected readonly as keyof is infer satisfies"

    private static let lexers: [ContentLanguage: Lexer] = [
        .json: Lexer([
            (slashComments, .comment),
            (#""[^"\\\n]*+(?:\\.[^"\\\n]*+)*+"(?=\s*:)"#, .property),
            (dq, .string),
            (#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
            (words("true false null"), .literal),
        ]),
        .javascript: Lexer([
            (slashComments, .comment),
            (#"`[^`\\]*+(?:\\[\s\S][^`\\]*+)*+`?"#, .string),
            (dq + "|" + sq, .string),
            (words(jsKeywords), .keyword),
            (words("true false null undefined NaN Infinity"), .literal),
            (number, .number),
            (call, .function),
            (capitalized, .type),
            (#"(?<=\.)[a-zA-Z_$][\w$]*"#, .property),
        ]),
        .typescript: Lexer([
            (slashComments, .comment),
            (#"`[^`\\]*+(?:\\[\s\S][^`\\]*+)*+`?"#, .string),
            (dq + "|" + sq, .string),
            (words(tsKeywords), .keyword),
            (words("true false null undefined NaN Infinity"), .literal),
            (words("string number boolean any unknown never void object symbol bigint"), .type),
            (number, .number),
            (call, .function),
            (capitalized, .type),
            (#"(?<=\.)[a-zA-Z_$][\w$]*"#, .property),
        ]),
        .python: Lexer([
            (#"#.*"#, .comment),
            (#"[rRbBfFuU]{0,2}(?:"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z))"#, .string),
            (#"[rRbBfFuU]{0,2}(?:"# + dq + "|" + sq + ")", .string),
            (#"@[\w.]+"#, .attribute),
            (words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case"), .keyword),
            (words("True False None"), .literal),
            (words("self cls"), .variable),
            (number, .number),
            (#"(?<=\bdef\s)\w+"#, .function),
            (#"(?<=\bclass\s)\w+"#, .type),
            (call, .function),
            (capitalized, .type),
        ]),
        .swift: Lexer([
            (slashComments, .comment),
            (#""""[\s\S]*?(?:"""|\z)"#, .string),
            (dq, .string),
            (#"@\w+|#\w+"#, .attribute),
            (words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as catch is throw throws try async await actor some any self Self super nonisolated isolated mutating override final lazy weak unowned convenience required get set willSet didSet"), .keyword),
            (words("true false nil"), .literal),
            (number, .number),
            (call, .function),
            (capitalized, .type),
            (#"(?<=\.)[a-zA-Z_]\w*"#, .property),
        ]),
        .css: Lexer([
            (#"/\*[\s\S]*?(?:\*/|\z)"#, .comment),
            (dq + "|" + sq, .string),
            (#"@[\w-]+|!important\b"#, .keyword),
            (#"#[0-9a-fA-F]{3,8}\b"#, .number),
            (#"[\w-]+(?=\s*:[^{\n]*(?:;|$))"#, .property),
            (#"(?:^|(?<=[{};]))[ \t]*+[^{}\n;\s][^{}\n;]*+(?=\{)"#, .tag),
            (#"-?(?:\b\d+(?:\.\d+)?|\.\d+)(?:[a-zA-Z]+|%)?"#, .number),
            (call, .function),
        ], [.anchorsMatchLines]),
        .yaml: Lexer([
            (#"(?:^|(?<=\s))#.*"#, .comment),
            (#"^(?:---|\.\.\.)[ \t]*$"#, .punctuation),
            (dq + "|" + sq, .string),
            (#"^[ \t]*-(?=[ \t]|$)"#, .listMarker),
            (#"[&*][\w-]+"#, .variable),
            (#"(?i:\b(?:true|false|null|yes|no|on|off)\b)|~"#, .literal),
            (#"-?\b\d+(?:\.\d+)?\b"#, .number),
        ], [.anchorsMatchLines]),
        .sql: Lexer([
            (#"--.*|/\*[\s\S]*?(?:\*/|\z)"#, .comment),
            (#"'[^'\n]*+(?:''[^'\n]*+)*+'?"#, .string),
            (#""[^"\n]*"?|`[^`\n]*`?"#, .property),
            (#"(?i:\b(?:null|true|false)\b)"#, .literal),
            (#"(?i:"# + words("select from where and or not insert into values update set delete create table index view drop alter add column primary key foreign references join left right inner outer full cross on as group by order having limit offset union all distinct case when then else end is in exists between like ilike asc desc default constraint unique check with returning begin commit rollback transaction if database schema grant revoke cascade truncate replace using natural over partition") + ")", .keyword),
            (#"(?i:"# + words("int integer bigint smallint text varchar char boolean bool date time timestamp timestamptz decimal numeric float real double serial uuid json jsonb blob") + ")", .type),
            (number, .number),
            (call, .function),
        ]),
        .shell: Lexer([
            (#"(?:^|(?<=[\s;]))#.*"#, .comment),
            (#""[^"\\]*+(?:\\[\s\S][^"\\]*+)*+"?"#, .string),
            (#"'[^']*'?"#, .string),
            (#"\$(?:\{[^}\n]*\}?|\w+|[@#?$!*0-9-])"#, .variable),
            (words("if then else elif fi for while until do done case esac in function return exit local export readonly declare unset shift break continue select time"), .keyword),
            (words("echo printf cd ls cat grep sed awk cut sort uniq head tail find xargs mkdir rm cp mv touch chmod chown ln curl wget git brew npm npx yarn pnpm pip pip3 python python3 node swift make docker kubectl ssh scp tar zip unzip open defaults launchctl sudo source alias test read eval exec set trap wait kill ps tee wc tr date sleep env which"), .function),
            (#"(?<=\s)--?[A-Za-z][\w-]*"#, .attribute),
            (#"\b\d+\b"#, .number),
        ], [.anchorsMatchLines]),
    ]
}

/// One pass over the text with every rule joined into a single expression, so a string hides the comment marks inside it and vice versa.
private struct Lexer: Sendable {
    let expression: NSRegularExpression
    let kinds: [SyntaxKind]

    // Each rule becomes one capturing group; rules themselves use only non-capturing groups.
    init(_ rules: [(String, SyntaxKind)], _ options: NSRegularExpression.Options = []) {
        expression = SyntaxHighlighter.regex(rules.map { "(" + $0.0 + ")" }.joined(separator: "|"), options)
        kinds = rules.map(\.1)
        precondition(expression.numberOfCaptureGroups == kinds.count, "A lexer rule must use only non-capturing groups")
    }

    func tokens(in text: String, range: NSRange) -> [SyntaxToken] {
        guard range.length > 0 else { return [] }
        return expression.matches(in: text, options: [.withTransparentBounds], range: range).compactMap { match in
            guard match.range.length > 0,
                  let group = (1...kinds.count).first(where: { match.range(at: $0).location != NSNotFound }) else { return nil }
            return SyntaxToken(match.range, kinds[group - 1])
        }
    }
}
