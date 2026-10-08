import AppKit
import SwiftUI

extension AppModel {
    func toggleSidebar() {
        withAnimation { sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly }
    }

    /// ⌘B as in VS Code: Bold while typing in a Markdown note (the Format menu takes it), the sidebar everywhere else.
    func handleSidebarShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "b",
              !(canFormatMarkdown && editor.hasFocus) else { return false }
        toggleSidebar()
        return true
    }
}
