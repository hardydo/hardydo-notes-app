import HardydoNotesCore
import SwiftUI

struct ContentView: View {
    let model: AppModel
    @StateObject private var detailFrame = ObservedState(CGRect.zero)

    private var store: NoteStore { model.store }
    private var dialogs: DialogModel { model.dialogs }

    var body: some View {
        NavigationSplitView(columnVisibility: Bindable(model.layout).sidebarVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            WorkspaceDetail(model: model, detailFrame: detailFrame)
        }
        .toolbar { WorkspaceToolbar(model: model) }
        // The toolbar title grabs presses for its own menu, so the window could not be dragged by it; the tab already names the note.
        .toolbar(removing: .title)
        // The system toolbar background starts a few points left of the sidebar divider; the detail draws its own instead so the edges line up.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // Centred over the editor side, under the view mode switcher, rather than over the whole window.
        .overlay(alignment: .topLeading) { QuickOpenLayer(quickOpen: model.quickOpen, actions: model.quickOpenActions, area: detailFrame) }
        .sheet(item: Binding(
            get: { dialogs.pendingDelete.flatMap(store.note) },
            set: { if $0 == nil { dialogs.pendingDelete = nil } }
        )) { note in
            DeleteConfirmation(message: "“\(note.title)” will be removed from this Mac. This can’t be undone.") {
                dialogs.pendingDelete = nil
            } onDelete: {
                model.confirmDelete()
            }
        }
        .sheet(isPresented: Bindable(dialogs).isClearingEmptyNotes) {
            EmptyNotesConfirmation(notes: store.emptyNotes) {
                dialogs.isClearingEmptyNotes = false
            } onDelete: { chosen in
                model.confirmClearEmptyNotes(chosen)
            }
        }
        .alert("Rename Note", isPresented: Binding(
            get: { dialogs.pendingRename != nil },
            set: { if !$0 { dialogs.pendingRename = nil } }
        )) {
            TextField("Name", text: Bindable(dialogs).renameText)
            Button("Rename") { model.confirmRename() }
            Button("Cancel", role: .cancel) { dialogs.pendingRename = nil }
        } message: {
            Text("Leave the name empty to use the note’s first line again.")
        }
        .sheet(isPresented: Bindable(model.workspace).isInsertingTable) {
            TableSheet(preferences: model.preferences) { rows, columns in model.workspace.controller.perform(.table(rows: rows, columns: columns)) }
        }
        .alert(dialogs.alert?.title ?? "", isPresented: Binding(
            get: { dialogs.alert != nil },
            set: { if !$0 { dialogs.alert = nil } }
        ), presenting: dialogs.alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .alert("File Changed on Disk", isPresented: Binding(
            get: { store.fileConflict != nil },
            set: { _ in }
        ), presenting: store.fileConflict) { _ in
            Button("Keep My Version") { store.resolveFileConflict(keepAppVersion: true) }
            Button("Use Version on Disk") { store.resolveFileConflict(keepAppVersion: false) }
        } message: { conflict in
            Text("“\(conflict.name)” was changed by another app while you were editing it here. Keeping your version overwrites the file; using the version on disk discards what you just typed.")
        }
        .alert("Storage Problem", isPresented: Binding(
            get: { model.storageProblem != nil },
            set: { if !$0 { model.dismissStorageProblem() } }
        )) {
            Button("OK") { model.dismissStorageProblem() }
        } message: {
            Text(model.storageProblem ?? "")
        }
    }
}

/// Everything that follows the open note, kept out of ContentView so switching notes leaves the toolbar and sheets alone.
private struct WorkspaceDetail: View {
    let model: AppModel
    let detailFrame: ObservedState<CGRect>

    private var store: NoteStore { model.store }

    var body: some View {
        VStack(spacing: 0) {
            if !model.tabs.list.ids.isEmpty {
                TabBar(tabs: model.tabs, actions: model.tabActions).equatable()
            }
            if let (note, text) = model.workspace.note.map({ ($0.summary, store.text(of: $0)) }) {
                BreadcrumbBar(workspace: model.workspace, groups: model.groups, note: note, revision: text.revision, language: model.workspace.language)
                if model.find.isShown {
                    FindBar(find: model.find)
                }
                GeometryReader { geometry in
                    let editorWidth = model.workspace.viewMode == .split ? geometry.size.width * model.layout.splitRatio : geometry.size.width
                    HStack(spacing: 0) {
                        if model.workspace.viewMode != .preview {
                            editor(note, text).frame(width: max(0, editorWidth))
                        }
                        if model.workspace.viewMode == .split {
                            SplitDivider(width: geometry.size.width) { model.layout.dragSplit(to: $0) } onEnd: { model.layout.endSplitDrag() }
                        }
                        if model.workspace.viewMode != .edit {
                            PreviewView(text: text, language: model.workspace.language, zoom: model.layout.zoom, syncsScroll: model.workspace.isSyncingScroll, workspace: model.workspace)
                                .background(PreviewView.pageBackground)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .coordinateSpace(.named(SplitDivider.space))
                }
            } else {
                EmptyWorkspace(model: model)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .overlay(alignment: .top) { Divider() }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { detailFrame.value = $0 }
        .background(WindowTitle(title: model.workspace.note?.title ?? AppInfo.name))
        .task(id: model.workspace.languageKey) { await model.workspace.refreshLanguage() }
    }

    private func editor(_ note: NoteSummary, _ text: NoteText) -> some View {
        EditorView(
            text: text,
            language: model.workspace.language,
            isEditable: !note.isLocked,
            zoom: model.layout.zoom,
            highlights: model.find.isShown ? model.find.ranges : [],
            currentHighlight: model.find.isShown ? model.find.current : nil,
            controller: model.workspace.controller,
            onEscape: { [model] in
                guard model.find.isShown else { return false }
                model.find.close()
                return true
            },
            onEdit: { [model] in model.tabs.keep(note.id) }
        ) { [store] text in
            store.updateBody(note.id, text)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if note.isLocked {
                LockedBanner { model.workspace.setLocked(note.id, false) }
            }
        }
    }
}

/// Reads the detail's frame itself, so resizing the window or the sidebar does not redraw the workspace around it.
private struct QuickOpenLayer: View {
    let quickOpen: QuickOpenModel
    let actions: QuickOpenActions
    let area: ObservedState<CGRect>

    var body: some View {
        if let mode = quickOpen.mode {
            let area = area.value
            QuickOpenView(quickOpen: quickOpen, actions: actions, mode: mode, width: min(680, max(320, area.width - 48)))
                .frame(width: area.width)
                .offset(x: area.minX)
        }
    }
}

// A SwiftUI navigation title rebuilds every toolbar item when it changes, so the window title is set directly.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async {
            if let window = nsView.window, window.title != title { window.title = title }
        }
    }
}
