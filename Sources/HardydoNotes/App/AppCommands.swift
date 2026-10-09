import HardydoNotesCore
import SwiftUI

/// The menu bar. Shortcuts follow VS Code on macOS where they do not clash with the standard Mac ones.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        CommandGroup(replacing: .newItem) {
            Button("New Note") { model.newNote() }.keyboardShortcut("n")
            Button("Open…") { model.showOpenPanel() }.keyboardShortcut("o")
            Button("Go to Note…") { model.showQuickOpen() }.keyboardShortcut("p")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }.keyboardShortcut("s")
            Button("Export…") { model.exportCurrent() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.selection == nil)
            Divider()
            TabCommands(model: model)
            Divider()
            Button("Lock or Unlock Note") { model.toggleLock() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(model.selection == nil)
        }
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .textEditing) {
            FindCommands(model: model)
        }
        CommandMenu("Selection") {
            LineCommands(model: model)
        }
        CommandGroup(after: .toolbar) {
            ViewModeCommands(model: model)
        }
        CommandMenu("Go") {
            GoCommands(model: model)
        }
        CommandMenu("Format") {
            FormatCommands(editor: model.editor, enabled: model.canFormatMarkdown && model.editor.hasFocus) {
                model.isInsertingTable = true
            }
            Divider()
            Button("Format JSON") { model.formatDocument() }
                .keyboardShortcut("f", modifiers: [.shift, .option])
                .disabled(!model.canFormatDocument || !model.editor.hasFocus)
        }
    }
}

private struct TabCommands: View {
    let model: AppModel

    var body: some View {
        Button(model.selection == nil ? "Close Window" : "Close Tab") { model.closeCurrentTab() }
            .keyboardShortcut("w")
        Button("Close Other Tabs") { model.selection.map(model.closeOtherTabs) }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(!(model.selection.map(model.tabList.canCloseOthers) ?? false))
        Button("Close All Tabs") { model.closeAllTabs() }
            .disabled(!model.tabList.canCloseAll)
        Button("Reopen Closed Tab") { model.reopenClosedTab() }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!model.tabList.canReopen)
        if let selection = model.selection {
            let pinned = model.isTabPinned(selection)
            Button(pinned ? "Unpin Tab" : "Pin Tab") { model.setTabPinned(selection, !pinned) }
        }
    }
}

private struct GoCommands: View {
    let model: AppModel

    var body: some View {
        Button("Next Tab") { model.cycleTabs(by: 1) }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        Button("Previous Tab") { model.cycleTabs(by: -1) }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        Menu("Switch Tab") {
            Button("Next Tab") { model.cycleTabs(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { model.cycleTabs(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Tab") { model.cycleTabs(by: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { model.cycleTabs(by: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...8, id: \.self) { number in
                Button("Tab \(number)") { model.activateTab(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .control)
            }
            Button("Last Tab") { model.activateTab(at: model.tabList.ids.count - 1) }
                .keyboardShortcut("9", modifiers: .control)
        }
        .disabled(model.tabList.ids.count < 2)
        Divider()
        Button("Go to Note…") { model.showQuickOpen() }
        Button("Go to Line…") { model.showQuickOpen(.line) }
            .keyboardShortcut("g", modifiers: .control)
            .disabled(!model.canEditText)
    }
}

private struct ViewModeCommands: View {
    let model: AppModel

    var body: some View {
        mode("Editor", .edit, "1")
        mode("Editor and Preview", .split, "2")
        mode("Preview", .preview, "3")
        Button("Toggle Preview") { model.togglePreview() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        Button("Zoom In") { model.layout.setZoom(model.layout.zoom * 1.1) }
            .keyboardShortcut("=")
        Button("Zoom Out") { model.layout.setZoom(model.layout.zoom / 1.1) }
            .keyboardShortcut("-")
        Button("Actual Size") { model.layout.setZoom(1) }
            .keyboardShortcut("0")
        Divider()
        Group {
            Button("Fold") { model.editor.fold() }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Unfold") { model.editor.unfold() }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Button("Fold All") { model.editor.foldAll() }
                .keyboardShortcut("[", modifiers: [.command, .option, .shift])
            Button("Unfold All") { model.editor.unfoldAll() }
                .keyboardShortcut("]", modifiers: [.command, .option, .shift])
        }
        .disabled(model.selection == nil || model.viewMode == .preview)
        Divider()
    }

    private func mode(_ title: String, _ mode: ViewMode, _ key: KeyEquivalent) -> some View {
        Toggle(title, isOn: Binding(get: { model.viewMode == mode }, set: { if $0 { model.viewMode = mode } }))
            .keyboardShortcut(key, modifiers: [.command, .option])
    }
}

private struct FindCommands: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Find…") { model.openFind() }
                .keyboardShortcut("f")
            Button("Find and Replace…") { model.openFind(replace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find Next") { model.findNext() }
                .keyboardShortcut("g")
            Button("Find Previous") { model.findNext(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }
        .disabled(model.selection == nil)
        Divider()
        Button("Search All Notes") { model.toggleGlobalSearch() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
    }
}

private struct LineCommands: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Select Line") { model.selectLine() }
                .keyboardShortcut("l")
            Divider()
            Button("Move Line Up") { model.moveLines(.up) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Move Line Down") { model.moveLines(.down) }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Button("Copy Line Up") { model.copyLines(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.option, .shift])
            Button("Copy Line Down") { model.copyLines(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.option, .shift])
            Button("Delete Line") { model.deleteLines() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Insert Line Below") { model.insertLine(.down) }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Insert Line Above") { model.insertLine(.up) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Divider()
            Button("Indent Line") { model.indentLines() }
                .keyboardShortcut("]")
            Button("Outdent Line") { model.outdentLines() }
                .keyboardShortcut("[")
            Button("Toggle Line Comment") { model.toggleComment() }
                .keyboardShortcut("/")
        }
        .disabled(!model.canEditText || !model.editor.hasFocus)
    }
}

private struct FormatCommands: View {
    let editor: EditorController
    let enabled: Bool
    let insertTable: () -> Void

    var body: some View {
        Group {
            Button("Bold") { editor.perform(.wrap("**")) }.keyboardShortcut("b")
            Button("Italic") { editor.perform(.wrap("*")) }.keyboardShortcut("i")
            Button("Strikethrough") { editor.perform(.wrap("~~")) }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { editor.perform(.wrap("`")) }.keyboardShortcut("e")
            Button("Link") { editor.perform(.link) }.keyboardShortcut("k")
            Divider()
            Button("Heading 1") { editor.perform(.line(.heading(1))) }.keyboardShortcut("1")
            Button("Heading 2") { editor.perform(.line(.heading(2))) }.keyboardShortcut("2")
            Button("Heading 3") { editor.perform(.line(.heading(3))) }.keyboardShortcut("3")
            Divider()
            Button("Bulleted List") { editor.perform(.line(.bullet)) }.keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { editor.perform(.line(.numbered)) }.keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Checklist") { editor.perform(.line(.task)) }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Quote") { editor.perform(.line(.quote)) }.keyboardShortcut(".", modifiers: [.command, .shift])
            Divider()
            Button("Insert Table…", action: insertTable).keyboardShortcut("t", modifiers: [.command, .option])
            Button("Insert Horizontal Rule") { editor.perform(.rule) }.keyboardShortcut("-", modifiers: [.command, .option])
        }
        .disabled(!enabled)
    }
}
