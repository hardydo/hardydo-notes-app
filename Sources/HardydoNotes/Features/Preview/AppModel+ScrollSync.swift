import Foundation

extension AppModel {
    /// In split view the preview keeps to the lines at the top of the editor, and the editor to the preview's.
    func toggleScrollSync() {
        layout.toggleScrollSync()
        alignPreview()
    }

    func connectScrollSync() {
        editor.onScroll = { [weak self] in self?.alignPreview() }
    }

    /// The preview's page, made the first time a preview shows so a window that never previews never starts WebKit.
    func previewPage() -> PreviewPage {
        if let preview { return preview }
        let page = PreviewPage()
        page.onShow = { [weak self] in self?.alignPreview() }
        page.onScroll = { [weak self] line in
            guard let self, isSyncingScroll else { return }
            editor.scroll(toLine: line)
        }
        preview = page
        return page
    }

    var isSyncingScroll: Bool {
        layout.isScrollSynced && viewMode == .split
    }

    private func alignPreview() {
        guard isSyncingScroll, let line = editor.topLine else { return }
        preview?.scroll(toLine: line)
    }
}
