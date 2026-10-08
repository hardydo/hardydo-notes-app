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

    /// Open tabs come first when nothing is typed, as recently used notes do in VS Code.
    func quickOpenNotes(matching query: String) -> [Note] {
        let open = tabList.ids.compactMap(store.note)
        let openIDs = Set(open.map(\.id))
        let candidates = open + (groups.orderedNotes(store.appNotes) + store.localFileNotes).filter { !openIDs.contains($0.id) }
        return FuzzyMatch.rank(candidates, query: query) { $0.title }
    }

    var selectedLineCount: Int {
        guard let note = selectedNote else { return 0 }
        return CodeFolding.lineStarts(note.body as NSString).count
    }
}
