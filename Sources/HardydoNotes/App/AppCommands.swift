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
            Button("Go to Note…") { model.quickOpen.show() }.keyboardShortcut("p")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }.keyboardShortcut("s")
            Button("Export…") { model.exportCurrent() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.tabs.selection == nil)
            Divider()
            TabCommands(model: model)
            Divider()
            Button("Lock or Unlock Note") { model.workspace.toggleLock() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(model.tabs.selection == nil)
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
            FormatCommands(editor: model.workspace.controller, enabled: model.workspace.canFormatMarkdown && model.workspace.controller.hasFocus) {
                model.workspace.isInsertingTable = true
            }
            Divider()
            Button("Format JSON") { model.workspace.formatDocument() }
                .keyboardShortcut("f", modifiers: [.shift, .option])
                .disabled(!model.workspace.canFormatDocument || !model.workspace.controller.hasFocus)
        }
    }
}

private struct TabCommands: View {
    let model: AppModel

    var body: some View {
        Button(model.tabs.selection == nil ? "Close Window" : "Close Tab") { model.tabs.closeCurrent() }
            .keyboardShortcut("w")
        Button("Close Other Tabs") { model.tabs.selection.map(model.tabs.closeOthers) }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(!(model.tabs.selection.map(model.tabs.list.canCloseOthers) ?? false))
        Button("Close All Tabs") { model.tabs.closeAll() }
            .disabled(!model.tabs.list.canCloseAll)
        Button("Reopen Closed Tab") { model.tabs.reopen() }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!model.tabs.list.canReopen)
        if let selection = model.tabs.selection {
            let pinned = model.tabs.isPinned(selection)
            Button(pinned ? "Unpin Tab" : "Pin Tab") { model.tabs.setPinned(selection, !pinned) }
        }
    }
}

private struct GoCommands: View {
    let model: AppModel

    var body: some View {
        Button("Next Tab") { model.tabs.cycle(by: 1) }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        Button("Previous Tab") { model.tabs.cycle(by: -1) }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        Menu("Switch Tab") {
            Button("Next Tab") { model.tabs.cycle(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { model.tabs.cycle(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Tab") { model.tabs.cycle(by: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { model.tabs.cycle(by: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...8, id: \.self) { number in
                Button("Tab \(number)") { model.tabs.activate(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .control)
            }
            Button("Last Tab") { model.tabs.activate(at: model.tabs.list.ids.count - 1) }
                .keyboardShortcut("9", modifiers: .control)
        }
        .disabled(model.tabs.list.ids.count < 2)
        Divider()
        Button("Go to Note…") { model.quickOpen.show() }
        Button("Go to Line…") { model.quickOpen.show(.line) }
            .keyboardShortcut("g", modifiers: .control)
            .disabled(!model.workspace.canEditText)
    }
}

private struct ViewModeCommands: View {
    let model: AppModel

    var body: some View {
        mode("Editor", .edit, "1")
        mode("Editor and Preview", .split, "2")
        mode("Preview", .preview, "3")
        Button("Toggle Preview") { model.workspace.togglePreview() }
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
            Button("Fold") { model.workspace.controller.fold() }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Unfold") { model.workspace.controller.unfold() }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Button("Fold All") { model.workspace.controller.foldAll() }
                .keyboardShortcut("[", modifiers: [.command, .option, .shift])
            Button("Unfold All") { model.workspace.controller.unfoldAll() }
                .keyboardShortcut("]", modifiers: [.command, .option, .shift])
        }
        .disabled(model.tabs.selection == nil || model.workspace.viewMode == .preview)
        Divider()
    }

    private func mode(_ title: String, _ mode: ViewMode, _ key: KeyEquivalent) -> some View {
        Toggle(title, isOn: Binding(get: { model.workspace.viewMode == mode }, set: { if $0 { model.workspace.viewMode = mode } }))
            .keyboardShortcut(key, modifiers: [.command, .option])
    }
}

private struct FindCommands: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Find…") { model.find.open() }
                .keyboardShortcut("f")
            Button("Find and Replace…") { model.find.open(replace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find Next") { model.find.next() }
                .keyboardShortcut("g")
            Button("Find Previous") { model.find.next(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }
        .disabled(model.tabs.selection == nil)
        Divider()
        Button("Search All Notes") { model.toggleGlobalSearch() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
    }
}

private struct LineCommands: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Select Line") { model.workspace.selectLine() }
                .keyboardShortcut("l")
            Divider()
            Button("Move Line Up") { model.workspace.moveLines(.up) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Move Line Down") { model.workspace.moveLines(.down) }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Button("Copy Line Up") { model.workspace.copyLines(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.option, .shift])
            Button("Copy Line Down") { model.workspace.copyLines(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.option, .shift])
            Button("Delete Line") { model.workspace.deleteLines() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Insert Line Below") { model.workspace.insertLine(.down) }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Insert Line Above") { model.workspace.insertLine(.up) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Divider()
            Button("Indent Line") { model.workspace.indentLines() }
                .keyboardShortcut("]")
            Button("Outdent Line") { model.workspace.outdentLines() }
                .keyboardShortcut("[")
            Button("Toggle Line Comment") { model.workspace.toggleComment() }
                .keyboardShortcut("/")
        }
        .disabled(!model.workspace.canEditText || !model.workspace.controller.hasFocus)
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
