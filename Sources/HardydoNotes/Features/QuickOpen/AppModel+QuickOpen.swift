import HardydoNotesCore
import Foundation

extension AppModel {
    var quickOpenActions: QuickOpenActions {
        QuickOpenActions(
            notes: { [self] query in
                let listed = (groups.list.orderedNotes(store.appNotes) + store.localFileNotes).map(\.summary)
                return FuzzyMatch.rank(QuickOpenRanking.candidates(openTabs: tabs.list.ids, listed: listed), query: query) { $0.title }
            },
            place: { [self] note in
                if let path = note.filePath { return (path as NSString).deletingLastPathComponent }
                return groups.list.group(of: note.id)?.displayName
            },
            lineCount: { [workspace] in workspace.lineCount },
            open: { [self] in tabs.open($0) },
            goToLine: { [workspace] line in
                workspace.leavePreview(to: .edit)
                workspace.goToLine(line)
            }
        )
    }
}
