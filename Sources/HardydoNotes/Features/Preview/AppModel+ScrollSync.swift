import Foundation

extension AppModel {
    /// In split view the preview keeps to the lines at the top of the editor, and the editor to the preview's.
    func toggleScrollSync() {
        isScrollSynced.toggle()
        defaults.set(isScrollSynced, forKey: Self.scrollSyncKey)
        alignPreview()
    }

    func connectScrollSync() {
        editor.onScroll = { [weak self] in self?.alignPreview() }
        PreviewPage.shared.onShow = { [weak self] in self?.alignPreview() }
        PreviewPage.shared.onScroll = { [weak self] line in
            guard let self, isSyncingScroll else { return }
            editor.scroll(toLine: line)
        }
    }

    private var isSyncingScroll: Bool {
        isScrollSynced && viewMode == .split
    }

    private func alignPreview() {
        guard isSyncingScroll, let line = editor.topLine else { return }
        PreviewPage.shared.scroll(toLine: line)
    }
}
