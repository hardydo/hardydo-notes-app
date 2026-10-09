import AppKit
import HardydoNotesCore
import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let text: NoteText
    let language: ContentLanguage
    let zoom: CGFloat
    let syncsScroll: Bool
    let model: AppModel

    /// The page's own background, drawn behind the web view so nothing else shows while it catches up.
    static let pageBackground = Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)

    func makeNSView(context: Context) -> WKWebView {
        model.previewPage().attach()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        let page = model.previewPage()
        page.syncsScroll = syncsScroll
        page.show(text, language: language)
    }
}

/*
 One page for the whole window, made the first time a preview shows: showing the preview again reuses the loaded
 page rather than starting WebKit over, which flashed on every switch. A page shown again stays hidden until it
 holds the current note.
 */
@MainActor
final class PreviewPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private struct Shown: Equatable {
        var text: NoteText?
        var language: ContentLanguage
    }

    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var latest = Shown(text: nil, language: .markdown)
    /// What the page holds, or is being given.
    private var rendered: Shown?
    private var isReady = false
    private var isRevealing = false
    private var renderTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?
    /// The line at the top of the page, each time the reader scrolls it.
    var onScroll: (Double) -> Void = { _ in }
    /// Called whenever the page shows the current note, so a synced scroll can line it up again.
    var onShow: () -> Void = {}
    var syncsScroll = false {
        didSet { if syncsScroll != oldValue { sendScrollSync() } }
    }

    override init() {
        super.init()
        webView.configuration.userContentController.add(self, name: "ready")
        webView.configuration.userContentController.add(self, name: "scroll")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    func attach() -> WKWebView {
        isRevealing = rendered != nil
        if isRevealing { webView.alphaValue = 0 }
        return webView
    }

    func show(_ text: NoteText, language: ContentLanguage) {
        let next = Shown(text: text, language: language)
        guard next != latest || rendered == nil || isRevealing else { return }
        latest = next
        if rendered == nil {
            load()
        } else if isReady, isRevealing {
            render()
        } else if isReady {
            scheduleRender()
        }
    }

    private func load() {
        isReady = false
        rendered = latest
        build(latest, page: true) { [weak self] html in self?.webView.loadHTMLString(html, baseURL: nil) }
    }

    // Typing in split view sends a change per keystroke; rendering once they pause keeps the editor responsive.
    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    private func render() {
        renderTask?.cancel()
        guard rendered != latest else {
            if buildTask == nil { reveal() }
            return
        }
        rendered = latest
        build(latest, page: false) { [weak self] html in
            self?.webView.callAsyncJavaScript("render(html)", arguments: ["html": html], in: nil, in: .page) { _ in self?.reveal() }
        }
    }

    // Converting a long note takes tens of milliseconds, so it happens off the main thread and a newer note drops it.
    private func build(_ shown: Shown, page: Bool, apply: @escaping (String) -> Void) {
        buildTask?.cancel()
        let string = shown.text?.string ?? "", language = shown.language
        buildTask = Task { [weak self] in
            let html = await Task.detached(priority: .userInitiated) {
                page
                    ? MarkdownHTML.page(string, language: language, sourceLines: true, highlightLimit: MarkdownHTML.previewHighlightLimit)
                    : MarkdownHTML.content(string, language: language, sourceLines: true, highlightLimit: MarkdownHTML.previewHighlightLimit)
            }.value
            guard let self, !Task.isCancelled else { return }
            buildTask = nil
            apply(html)
        }
    }

    private func reveal() {
        onShow()
        guard isRevealing else { return }
        isRevealing = false
        webView.alphaValue = 1
    }

    private func sendScrollSync() {
        guard isReady else { return }
        webView.callAsyncJavaScript("setScrollSync(on)", arguments: ["on": syncsScroll], in: nil, in: .page)
    }

    func scroll(toLine line: Double) {
        guard isReady else { return }
        webView.callAsyncJavaScript("scrollToLine(line)", arguments: ["line": line], in: nil, in: .page)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "scroll" {
            if let line = message.body as? Double { onScroll(line) }
            return
        }
        isReady = true
        sendScrollSync()
        render()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.navigationType == .linkActivated, let url = action.request.url, url.scheme != "about" else {
            return .allow
        }
        // Only web and mail links leave the preview; other schemes could launch any app.
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return .cancel
    }
}
