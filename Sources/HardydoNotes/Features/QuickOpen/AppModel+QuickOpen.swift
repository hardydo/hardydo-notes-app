import HardydoNotesCore
import Foundation

enum QuickOpenMode: Equatable {
    case notes
    case line
}

extension AppModel {
    func showQuickOpen(_ mode: QuickOpenMode = .notes) {
        editor.commit()
        quickOpen = mode
    }

    func closeQuickOpen() {
        quickOpen = nil
        editor.focus()
    }

    func quickOpenNotes(matching query: String) -> [NoteSummary] {
        let listed = (groups.orderedNotes(store.appNotes) + store.localFileNotes).map(\.summary)
        return FuzzyMatch.rank(QuickOpenRanking.candidates(openTabs: tabList.ids, listed: listed), query: query) { $0.title }
    }

    var selectedLineCount: Int {
        guard let note = selectedNote else { return 0 }
        return editor.lineCount ?? LineIndex(note.body as NSString).count
    }
}
