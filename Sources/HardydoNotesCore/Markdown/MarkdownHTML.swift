import Foundation
import cmark_gfm
import cmark_gfm_extensions

public enum MarkdownHTML {
    private static let extensions = ["table", "strikethrough", "autolink", "tasklist"]
    private static let options = CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES

    /// `sourceLines` tags each block with the source lines it came from, which the preview follows to scroll in step with the editor.
    public static func body(_ markdown: String, sourceLines: Bool = false) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        let options = sourceLines ? options | CMARK_OPT_SOURCEPOS : options
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensions {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Code longer than this shows uncoloured: highlight.js would freeze the page for seconds on it.
    public static let exportHighlightLimit = 500_000
    /// The live preview recolours a note on every pause in typing, so it gives up much sooner than an export.
    public static let previewHighlightLimit = 100_000

    /// Markdown renders as a page; code shows as one highlighted block and plain text as it is typed.
    public static func content(_ text: String, language: ContentLanguage = .markdown, sourceLines: Bool = false, highlightLimit: Int = exportHighlightLimit) -> String {
        if language == .markdown {
            return body(text, sourceLines: sourceLines).replacingOccurrences(of: #" disabled="""#, with: "")
        }
        let lines = text.reduce(into: 1) { count, character in if character.isNewline { count += 1 } }
        let source = sourceLines ? " data-sourcepos=\"1:1-\(lines):1\"" : ""
        if language == .plainText || text.utf16.count > highlightLimit {
            return "<pre class=\"plain\"\(source)>" + escape(text) + "</pre>"
        }
        return "<pre\(source)><code class=\"language-\(language.highlightName ?? "plaintext")\">" + escape(text) + "</code></pre>"
    }

    /// highlight.js and its GitHub themes, written into every page so the preview and exports never reach the network.
    public struct Highlighter: Sendable {
        let script: String
        let darkTheme: String
        let lightTheme: String

        public init?(directory: URL) {
            func read(_ name: String) -> String? { try? String(contentsOf: directory.appending(path: name), encoding: .utf8) }
            guard let script = read("highlight.min.js"), let darkTheme = read("github-dark.min.css"), let lightTheme = read("github.min.css") else { return nil }
            (self.script, self.darkTheme, self.lightTheme) = (script, darkTheme, lightTheme)
        }

        /// Absent outside the packaged app, where code shows uncoloured.
        public static let bundled = Bundle.main.resourceURL.flatMap { Highlighter(directory: $0.appending(path: "highlight")) }
    }

    public static func page(_ text: String, title: String? = nil, language: ContentLanguage = .markdown, sourceLines: Bool = false, highlightLimit: Int = exportHighlightLimit, highlighter: Highlighter? = .bundled) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">\(title.map { "\n<title>" + escape($0) + "</title>" } ?? "")
        <style>\(stylesheet)</style>\(highlighter.map { "\n<style media=\"screen\">" + $0.darkTheme + "</style>\n<style media=\"print\">" + $0.lightTheme + "</style>" } ?? "")
        </head>
        <body>
        <article id="content" class="markdown-body">\(content(text, language: language, sourceLines: sourceLines, highlightLimit: highlightLimit))</article>\(highlighter.map { "\n<script>" + $0.script + "</script>" } ?? "")
        <script>\(script)</script>
        </body>
        </html>
        """
    }

    static let script = """
    var source = [];
    function highlight() {
      if (!window.hljs) return;
      document.querySelectorAll('pre code[class*="language-"]:not([data-highlighted])').forEach(function (el) { hljs.highlightElement(el); });
    }
    // Source lines shift under every block below an edit; leaving them out of the comparison keeps those blocks in place.
    function markup(node) {
      return node.nodeType === 1 ? node.outerHTML.replace(/ data-sourcepos="[^"]*"/g, '') : node.textContent;
    }
    function render(html) {
      var next = document.createElement('article');
      next.innerHTML = html;
      var content = document.getElementById('content');
      var nodes = Array.prototype.slice.call(next.childNodes);
      nodes.forEach(function (node, i) {
        var html = markup(node);
        var current = content.childNodes[i];
        if (!current) content.appendChild(node);
        else if (source[i] !== html) content.replaceChild(node, current);
        else if (node.nodeType === 1 && node.dataset.sourcepos) current.dataset.sourcepos = node.dataset.sourcepos;
        source[i] = html;
      });
      while (content.childNodes.length > nodes.length) content.removeChild(content.lastChild);
      source.length = nodes.length;
      highlight();
      measured = null;
    }
    source = Array.prototype.map.call(document.getElementById('content').childNodes, markup);
    highlight();
    /*
     Lines are 1-based and fractional: 12.5 is halfway down line 12. Each top-level block knows the lines it came
     from, so a line maps into its block by proportion, and a line between two blocks into the gap between them.
     */
    var measured = null;
    function blocks() {
      if (measured) return measured;
      var scrollTop = document.scrollingElement.scrollTop;
      return measured = Array.prototype.filter.call(document.getElementById('content').children, function (el) {
        return el.dataset.sourcepos;
      }).map(function (el) {
        var lines = el.dataset.sourcepos.split('-');
        var rect = el.getBoundingClientRect();
        return { start: parseInt(lines[0], 10), end: parseInt(lines[1], 10) + 1, top: rect.top + scrollTop, bottom: rect.bottom + scrollTop };
      });
    }
    function between(value, from, to, outFrom, outTo) {
      return to > from ? outFrom + (value - from) / (to - from) * (outTo - outFrom) : outFrom;
    }
    // Blocks run down the page in source order, so both their ends and their bottoms only ever grow.
    function firstPast(list, key, value) {
      var low = 0, high = list.length;
      while (low < high) {
        var middle = (low + high) >> 1;
        if (list[middle][key] > value) high = middle; else low = middle + 1;
      }
      return low;
    }
    function offsetOfLine(line) {
      var list = blocks(), i = firstPast(list, 'end', line);
      var previous = i > 0 ? list[i - 1] : { end: 1, bottom: 0 };
      if (i === list.length) return previous.bottom;
      var block = list[i];
      if (line < block.start) return between(line, previous.end, block.start, previous.bottom, block.top);
      return between(line, block.start, block.end, block.top, block.bottom);
    }
    function lineAtOffset(offset) {
      var list = blocks(), i = firstPast(list, 'bottom', offset);
      var previous = i > 0 ? list[i - 1] : { end: 1, bottom: 0 };
      if (i === list.length) return previous.end;
      var block = list[i];
      if (offset < block.top) return between(offset, previous.bottom, block.top, previous.end, block.start);
      return between(offset, block.top, block.bottom, block.start, block.end);
    }
    // Images loading, fonts settling and the window resizing all move blocks after a render.
    new ResizeObserver(function () { measured = null; }).observe(document.getElementById('content'));
    // A scroll the editor asked for must not echo back to it as the reader's own.
    var followingUntil = 0;
    function scrollToLine(line) {
      followingUntil = Date.now() + 150;
      document.scrollingElement.scrollTop = offsetOfLine(line);
    }
    var isSyncing = false, isScrollQueued = false;
    function setScrollSync(on) { isSyncing = on; }
    window.addEventListener('scroll', function () {
      if (!isSyncing || isScrollQueued || !window.webkit || !window.webkit.messageHandlers.scroll) return;
      isScrollQueued = true;
      requestAnimationFrame(function () {
        isScrollQueued = false;
        if (!isSyncing || Date.now() < followingUntil) return;
        window.webkit.messageHandlers.scroll.postMessage(lineAtOffset(document.scrollingElement.scrollTop));
      });
    }, { passive: true });
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ready) {
      window.webkit.messageHandlers.ready.postMessage(true);
    }
    """

    static let stylesheet = """
    :root {
      color-scheme: dark;
      --fg: #f0f6fc; --muted: #9198a1; --bg: #0d1117; --border: #3d444d;
      --border-muted: #3d444db3; --code-bg: #656c7633; --pre-bg: #151b23;
      --link: #4493f8; --row-alt: #151b23; --mark: #bb800926;
    }
    /* Paper stays white: a printed or exported PDF in the dark colours would waste ink and lose its background. */
    @media print {
      :root {
        color-scheme: light;
        --fg: #1f2328; --muted: #59636e; --bg: #ffffff; --border: #d1d9e0;
        --border-muted: #d1d9e0b3; --code-bg: #818b981f; --pre-bg: #f6f8fa;
        --link: #0969da; --row-alt: #f6f8fa; --mark: #fff8c5;
      }
    }
    html, body { margin: 0; background: var(--bg); }
    ::-webkit-scrollbar { width: 10px; height: 10px; }
    ::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
    ::-webkit-scrollbar-thumb { background: rgba(128, 128, 128, 0.4); border: 2.5px solid transparent; background-clip: padding-box; }
    .markdown-body {
      box-sizing: border-box; margin: 0; padding: 20px 29px 64px 49px;
      color: var(--fg); font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
      word-wrap: break-word;
    }
    .markdown-body > *:first-child { margin-top: 0 !important; }
    .markdown-body p, .markdown-body blockquote, .markdown-body ul, .markdown-body ol,
    .markdown-body table, .markdown-body pre, .markdown-body details { margin: 0 0 16px; }
    .markdown-body h1, .markdown-body h2, .markdown-body h3,
    .markdown-body h4, .markdown-body h5, .markdown-body h6 {
      margin: 24px 0 16px; font-weight: 600; line-height: 1.25;
    }
    .markdown-body h1 { font-size: 1.733em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    .markdown-body h2 { font-size: 1.467em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    .markdown-body h3 { font-size: 1.267em; }
    .markdown-body h4 { font-size: 1.133em; }
    .markdown-body h5 { font-size: 1.067em; }
    .markdown-body h6 { font-size: 1em; color: var(--muted); }
    .markdown-body a { color: var(--link); text-decoration: none; }
    .markdown-body a:hover { text-decoration: underline; }
    .markdown-body strong { font-weight: 600; }
    .markdown-body del { color: var(--muted); }
    .markdown-body hr { height: .25em; margin: 24px 0; padding: 0; border: 0; background: var(--border); }
    .markdown-body blockquote { padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); }
    .markdown-body blockquote > :last-child { margin-bottom: 0; }
    .markdown-body ul, .markdown-body ol { padding-left: 2em; }
    .markdown-body ul ul, .markdown-body ul ol, .markdown-body ol ol, .markdown-body ol ul { margin: 0; }
    .markdown-body li + li { margin-top: .25em; }
    .markdown-body li:has(> input[type="checkbox"]) { list-style: none; }
    .markdown-body ul:has(> li > input[type="checkbox"]) { padding-left: 1.2em; }
    .markdown-body input[type="checkbox"] { margin: 0 .3em .2em -1.4em; vertical-align: middle; accent-color: var(--link); pointer-events: none; }
    .markdown-body code, .markdown-body pre {
      font: 85%/1.45 ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
    }
    .markdown-body code { padding: .2em .4em; border-radius: 6px; background: var(--code-bg); white-space: break-spaces; }
    .markdown-body pre { padding: 16px; overflow: auto; border-radius: 6px; background: var(--pre-bg); }
    .markdown-body pre code { padding: 0; font-size: 100%; background: transparent; white-space: pre; }
    .markdown-body pre code.hljs { padding: 0; background: transparent; }
    .markdown-body pre.plain { padding: 0; background: transparent; font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif; white-space: pre-wrap; }
    .markdown-body table { display: block; width: max-content; max-width: 100%; overflow: auto; border-spacing: 0; border-collapse: collapse; }
    .markdown-body th { font-weight: 600; }
    .markdown-body th, .markdown-body td { padding: 6px 13px; border: 1px solid var(--border); }
    .markdown-body tr:nth-child(2n) { background: var(--row-alt); }
    .markdown-body img { max-width: 100%; border-radius: 6px; }
    .markdown-body mark { background: var(--mark); color: inherit; }
    .markdown-body .footnotes { font-size: 12px; color: var(--muted); border-top: 1px solid var(--border); padding-top: 8px; }
    """
}
