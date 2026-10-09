import AppKit
import HardydoNotesCore
import SwiftUI

extension AppModel {
    var visibleNotes: [Note] {
        groups.list.visibleNotes(store.appNotes) + store.localFileNotes
    }

    func moveSelection(by offset: Int) {
        guard let id = groups.list.step(from: tabs.selection, by: offset, appNotes: store.appNotes, fileNotes: store.localFileNotes) else { return }
        tabs.open(id)
    }

    func toggleSidebar() {
        withAnimation { layout.sidebarVisibility = layout.sidebarVisibility == .detailOnly ? .all : .detailOnly }
    }

    /// ⌘B as in VS Code: Bold while typing in a Markdown note (the Format menu takes it), the sidebar everywhere else.
    func handleSidebarShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "b",
              !(workspace.canFormatMarkdown && workspace.controller.hasFocus) else { return false }
        toggleSidebar()
        return true
    }
}
