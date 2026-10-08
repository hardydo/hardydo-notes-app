import AppKit
import HardydoNotesCore
import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let text: String
    let language: ContentLanguage
    let zoom: CGFloat

    /// The page's own background, drawn behind the web view so nothing else shows while it catches up.
    static let pageBackground = Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)

    func makeNSView(context: Context) -> WKWebView {
        PreviewPage.shared.attach()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        PreviewPage.shared.show(text, language: language)
    }
}

/*
 One page for the whole app: showing the preview again reuses the loaded page rather than starting WebKit over,
 which flashed on every switch to Split or Preview. A page shown again stays hidden until it holds the current note.
 */
@MainActor
final class PreviewPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = PreviewPage()

    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var latest = (text: "", language: ContentLanguage.markdown)
    private var rendered: (text: String, language: ContentLanguage)?
    private var isReady = false
    private var isRevealing = false
    private var renderTask: Task<Void, Never>?
    /// The line at the top of the page, each time the reader scrolls it.
    var onScroll: (Double) -> Void = { _ in }
    /// Called whenever the page shows the current note, so a synced scroll can line it up again.
    var onShow: () -> Void = {}

    override private init() {
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

    func show(_ text: String, language: ContentLanguage) {
        guard text != latest.text || language != latest.language || rendered == nil || isRevealing else { return }
        latest = (text, language)
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
        webView.loadHTMLString(MarkdownHTML.page(latest.text, language: latest.language, sourceLines: true), baseURL: nil)
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
        guard rendered?.text != latest.text || rendered?.language != latest.language else { return reveal() }
        rendered = latest
        let html = MarkdownHTML.content(latest.text, language: latest.language, sourceLines: true)
        webView.callAsyncJavaScript("render(html)", arguments: ["html": html], in: nil, in: .page) { [weak self] _ in
            self?.reveal()
        }
    }

    private func reveal() {
        onShow()
        guard isRevealing else { return }
        isRevealing = false
        webView.alphaValue = 1
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
