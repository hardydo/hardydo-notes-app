import HardydoNotesCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @StateObject private var detailFrame = ViewState(CGRect.zero)

    private var store: NoteStore { model.store }

    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            detail
        }
        .navigationTitle(model.selectedNote?.title ?? "Hardydo Notes")
        .toolbar { WorkspaceToolbar(model: model) }
        // The toolbar title grabs presses for its own menu, so the window could not be dragged by it; the tab already names the note.
        .toolbar(removing: .title)
        // The system toolbar background starts a few points left of the sidebar divider; the detail draws its own instead so the edges line up.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // Centred over the editor side, under the view mode switcher, rather than over the whole window.
        .overlay(alignment: .topLeading) {
            if let mode = model.quickOpen {
                let area = detailFrame.value
                QuickOpenView(model: model, mode: mode, width: min(680, max(320, area.width - 48)))
                    .frame(width: area.width)
                    .offset(x: area.minX)
            }
        }
        .sheet(item: Binding(
            get: { model.pendingDelete.flatMap(store.note) },
            set: { if $0 == nil { model.pendingDelete = nil } }
        )) { note in
            DeleteConfirmation(message: "“\(note.title)” will be removed from this Mac. This can’t be undone.") {
                model.pendingDelete = nil
            } onDelete: {
                model.confirmDelete()
            }
        }
        .sheet(isPresented: $model.isClearingEmptyNotes) {
            DeleteConfirmation(heading: "Delete empty notes?", message: emptyNotesMessage) {
                model.isClearingEmptyNotes = false
            } onDelete: {
                model.confirmClearEmptyNotes()
            }
        }
        .alert("Rename Note", isPresented: Binding(
            get: { model.pendingRename != nil },
            set: { if !$0 { model.pendingRename = nil } }
        )) {
            TextField("Name", text: $model.renameText)
            Button("Rename") { model.confirmRename() }
            Button("Cancel", role: .cancel) { model.pendingRename = nil }
        } message: {
            Text("Leave the name empty to use the note’s first line again.")
        }
        .sheet(isPresented: $model.isInsertingTable) {
            TableSheet { rows, columns in model.editor.perform(.table(rows: rows, columns: columns)) }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        ), presenting: model.alert) { _ in
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
            get: { store.fileError != nil },
            set: { if !$0 { store.dismissFileError() } }
        )) {
            Button("OK") { store.dismissFileError() }
        } message: {
            Text(store.fileError ?? "")
        }
    }

    private var emptyNotesMessage: String {
        let count = store.emptyNotes.count
        let notes = count == 1 ? "1 note has" : "\(count) notes have"
        return "\(notes) no text at all and will be removed from this Mac. Notes with any text, and locked notes, are kept. This can’t be undone."
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if !model.tabList.ids.isEmpty {
                TabBar(model: model)
            }
            if let note = model.selectedNote {
                BreadcrumbBar(model: model, note: note, language: model.selectedLanguage)
                if model.showFind {
                    FindBar(model: model)
                }
                GeometryReader { geometry in
                    let editorWidth = model.viewMode == .split ? geometry.size.width * model.splitRatio : geometry.size.width
                    HStack(spacing: 0) {
                        if model.viewMode != .preview {
                            editor(note).frame(width: max(0, editorWidth))
                        }
                        if model.viewMode == .split {
                            SplitDivider(width: geometry.size.width) { model.dragSplit(to: $0) } onEnd: { model.endSplitDrag() }
                        }
                        if model.viewMode != .edit {
                            PreviewView(text: note.body, language: model.selectedLanguage, zoom: model.zoom)
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
    }

    private func editor(_ note: Note) -> some View {
        EditorView(
            text: note.body,
            language: model.selectedLanguage,
            isEditable: !note.isLocked,
            zoom: model.zoom,
            highlights: model.showFind ? model.findResult.ranges : [],
            currentHighlight: model.showFind ? model.findCurrent : nil,
            controller: model.editor,
            onEscape: { [model] in
                guard model.showFind else { return false }
                model.closeFind()
                return true
            },
            onEdit: { [model] in model.noteEdited(note.id) }
        ) { [store] text in
            store.updateBody(note.id, text)
        }
        .id(note.id)
        .safeAreaInset(edge: .top, spacing: 0) {
            if note.isLocked {
                LockedBanner { model.setLocked(note.id, false) }
            }
        }
    }
}
