import AppKit
import HardydoNotesCore
import UniformTypeIdentifiers
import WebKit

enum ExportFormat: Int, CaseIterable {
    case source
    case html
    case pdf

    func title(_ language: ContentLanguage) -> String {
        switch self {
        case .source: "\(language.name) (.\(language.fileExtension))"
        case .html: "Web Page (.html)"
        case .pdf: "PDF (.pdf)"
        }
    }

    func type(_ language: ContentLanguage) -> UTType {
        switch self {
        case .source: UTType(filenameExtension: language.fileExtension) ?? .plainText
        case .html: .html
        case .pdf: .pdf
        }
    }
}

@MainActor
final class NoteExporter: NSObject {
    private static let formatKey = "exportFormat"
    private weak var panel: NSSavePanel?
    private var pdf: PDFRenderer?
    private var language = ContentLanguage.markdown

    /// Asks where to save, then writes the note in its own format, as a web page or as a PDF; errors come back for the caller to show.
    func export(_ note: Note, language: ContentLanguage, from window: NSWindow?) async throws {
        guard panel == nil, pdf == nil else { return }
        let panel = NSSavePanel()
        self.panel = panel
        defer { self.panel = nil }
        self.language = language
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ExportFormat.allCases.map { $0.title(language) })
        popup.selectItem(at: AppPaths.defaults.integer(forKey: Self.formatKey))
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        let label = NSTextField(labelWithString: "Format:")
        let accessory = NSStackView(views: [label, popup])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let format = ExportFormat(rawValue: popup.indexOfSelectedItem) ?? .source
        panel.allowedContentTypes = [format.type(language)]
        panel.nameFieldStringValue = Self.baseName(of: note)

        let response = if let window { await panel.beginSheetModal(for: window) } else { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        let chosen = ExportFormat(rawValue: popup.indexOfSelectedItem) ?? .source
        AppPaths.defaults.set(chosen.rawValue, forKey: Self.formatKey)
        switch chosen {
        case .source:
            try Data(note.body.utf8).write(to: url, options: .atomic)
        case .html:
            try Data(MarkdownHTML.page(note.body, title: note.title, language: language).utf8).write(to: url, options: .atomic)
        case .pdf:
            let renderer = PDFRenderer()
            pdf = renderer
            defer { pdf = nil }
            try await renderer.render(MarkdownHTML.page(note.body, title: note.title, language: language), to: url)
        }
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let panel, let format = ExportFormat(rawValue: sender.indexOfSelectedItem) else { return }
        panel.allowedContentTypes = [format.type(language)]
    }

    private static func baseName(of note: Note) -> String {
        (note.fileName as NSString).deletingPathExtension
    }
}

/// Lays the preview page out on the printer's paper size; the page's print styles keep it light.
@MainActor
private final class PDFRenderer: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Void, Error>?

    func render(_ html: String, to url: URL) async throws {
        let paper = NSPrintInfo.shared.paperSize
        let webView = WKWebView(frame: NSRect(origin: .zero, size: paper))
        webView.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: paper.width, height: paper.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        defer { window.close() }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.finishLoading(CocoaError(.fileWriteUnknown))
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 24
        info.rightMargin = 24
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        let done = await withCheckedContinuation { continuation in
            operation.runModal(for: window, delegate: PrintCallback.shared, didRun: #selector(PrintCallback.printOperationDidRun(_:success:contextInfo:)), contextInfo: PrintCallback.shared.store(continuation))
        }
        guard done, FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func finishLoading(_ error: Error?) {
        guard let loaded else { return }
        self.loaded = nil
        if let error { loaded.resume(throwing: error) } else { loaded.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishLoading(CocoaError(.fileWriteUnknown))
    }
}

// Saving a print job to a file reports completion on a background thread.
private final class PrintCallback: NSObject, @unchecked Sendable {
    static let shared = PrintCallback()
    private let lock = NSLock()
    private var pending: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var next = 0

    func store(_ continuation: CheckedContinuation<Bool, Never>) -> UnsafeMutableRawPointer? {
        lock.withLock {
            next += 1
            pending[next] = continuation
            return UnsafeMutableRawPointer(bitPattern: next)
        }
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let key = Int(bitPattern: contextInfo)
        let continuation = lock.withLock { pending.removeValue(forKey: key) }
        continuation?.resume(returning: success)
    }
}
