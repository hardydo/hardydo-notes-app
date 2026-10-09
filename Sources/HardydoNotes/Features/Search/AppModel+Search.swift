import AppKit
import HardydoNotesCore

/// What the search of every note depends on; any change restarts it.
struct GlobalSearchInputs: Equatable {
    let query: String
    let options: SearchOptions
    let changeCount: Int
}

extension AppModel {
    var globalSearchInputs: GlobalSearchInputs {
        GlobalSearchInputs(query: globalSearch.query, options: find.options, changeCount: store.changeCount)
    }

    func runGlobalSearch() async {
        let notes = store.notes.map {
            SearchableNote(id: $0.id, revision: store.revision(of: $0.id), title: $0.title, isFile: $0.localFile != nil, body: $0.body)
        }
        await globalSearch.search(notes, options: find.options)
    }

    func openGlobalSearch() {
        workspace.controller.commit()
        sidebar.cancelDrags()
        globalSearch.isShown = true
        globalSearch.focusRequest += 1
    }

    func toggleGlobalSearch() {
        if globalSearch.isShown {
            closeGlobalSearch()
        } else {
            openGlobalSearch()
        }
    }

    func closeGlobalSearch() {
        globalSearch.isShown = false
    }

    func openResult(_ note: Note.ID, _ match: LineMatch) {
        find.query = globalSearch.query
        find.isShown = true
        let editor = workspace.controller
        let editorShown = workspace.viewMode != .preview && tabs.selection == note && editor.textView != nil
        workspace.leavePreview(to: .split)
        tabs.open(note)
        find.current = match.range
        if editorShown {
            editor.reveal(match.range)
        } else {
            editor.pendingReveal = match.range
        }
    }
}
