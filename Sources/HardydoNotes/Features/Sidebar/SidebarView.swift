import HardydoNotesCore
import SwiftUI

struct SidebarView: View {
    let model: AppModel

    // Resizing re-runs the reader's content, which compares equal, so the list is not rebuilt for every frame of a resize.
    var body: some View {
        GeometryReader { geometry in
            SidebarContent(model: model, topInset: geometry.safeAreaInsets.top)
        }
    }
}

private struct SidebarContent: View {
    let model: AppModel
    let topInset: CGFloat
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @StateObject private var listTop = ObservedState(CGFloat(0))

    // A plain stack instead of List: List's native highlight turns grey once the editor has focus, and its onMove never starts while rows handle taps.
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Group {
                    if model.globalSearch.isShown {
                        GlobalSearchField(model: model, search: model.globalSearch, isFocused: $isSearchFocused)
                    } else {
                        header
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, topInset + 6)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.globalSearch.isShown {
                            GlobalSearchResults(search: model.globalSearch, tabs: model.tabs, find: model.find, open: model.openResult)
                        } else {
                            SidebarList(model: model) { isListFocused = true }
                        }
                    }
                    .overlayPreferenceValue(GroupBarKey.self) { items in
                        GeometryReader { proxy in GroupBars(reorder: model.sidebar.reorder, groups: model.groups, items: items, proxy: proxy) }
                            .allowsHitTesting(false)
                    }
                    .coordinateSpace(.named("sidebar"))
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(FileDrop.space)).minY } action: { listTop.value = $0 }
                    .background(ThinScrollBar())
                    .background(ReorderScrollAnchor(sessions: [model.sidebar.reorder, model.sidebar.fileReorder]))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    model.sidebar.reorder.viewport = frame
                    model.sidebar.fileReorder.viewport = frame
                }
            }
            // The sidebar scroll view applies the toolbar inset twice on this macOS, leaving a gap; the toolbar height is padded in by hand instead.
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(.named(FileDrop.space))
            .onDrop(of: [.fileURL], delegate: FileDrop(model: model, listTop: listTop))
            .background(SelectionScroller(tabs: model.tabs, sidebar: model.sidebar, globalSearch: model.globalSearch, proxy: proxy))
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: model.moveSelection(by: -1)
                case .down: model.moveSelection(by: 1)
                default: break
                }
            }
            .onDeleteCommand {
                if model.visibleNotes.contains(where: { $0.id == model.tabs.selection }) { model.requestDelete(model.tabs.selection) }
            }
            .onChange(of: model.globalSearch.focusRequest) { isSearchFocused = true }
            .onAppear {
                if model.globalSearch.isShown { isSearchFocused = true }
            }
        }
    }

    private var header: some View {
        // At one point size the solid magnifier and the tall trash look bigger than the open square of the pencil.
        SectionHeader(title: AppInfo.name) {
            Button { model.openGlobalSearch() } label: { Image(systemName: "magnifyingglass").font(.system(size: 12.5)) }
                .help("Search All Notes (⇧⌘F)")
            Button { model.dialogs.isClearingEmptyNotes = true } label: { Image(systemName: "trash").font(.system(size: 12)) }
                .help("Delete Empty Notes…")
                .disabled(!model.store.hasEmptyNotes)
            Button { model.newNote() } label: { Image(systemName: "square.and.pencil") }
                .help("New Note (⌘N)")
        }
    }
}

/// The notes and groups. Each row is compared by what it shows, so a change redraws only the rows it touches.
private struct SidebarList: View {
    let model: AppModel
    let focusList: () -> Void

    var body: some View {
        let sidebar = model.sidebar
        let groups = model.groups
        let actions = NoteRowActions(model: model, focusList: focusList)
        let rows = groups.list.rows(for: model.store.appNotes)
        ForEach(rows) { row in
            LiftLayer(cell: sidebar.reorder.cell(row.id)) {
                switch row {
                case .header(let group):
                    SidebarGroupRow(sidebar: sidebar, groups: groups, group: group, newNote: model.newNote(inGroup:)).equatable()
                case .note(let note, let group):
                    SidebarNoteRow(sidebar: sidebar, groups: groups, note: note, group: group, actions: actions).equatable()
                }
            }
        }
        .onChange(of: rows.map(\.id)) { sidebar.reorder.cancel() }
        let files = model.store.localFileNotes
        if !files.isEmpty {
            SectionHeader(title: "Open Files") { EmptyView() }
                .padding(.top, 8)
            ForEach(files) { note in
                LiftLayer(cell: sidebar.fileReorder.cell(note.id)) {
                    SidebarFileRow(sidebar: sidebar, groups: groups, note: note.summary, actions: actions).equatable()
                }
            }
            .onChange(of: files.map(\.id)) { sidebar.fileReorder.cancel() }
        }
    }
}

/*
 Raises a lifted row above the rows it passes. A zIndex set inside an equatable row never reaches the stack, so it
 is set out here, where only this layer redraws when the row is lifted.
 */
private struct LiftLayer<Content: View>: View {
    let cell: ReorderCell
    @ViewBuilder let content: Content

    var body: some View {
        content.zIndex(cell.lift != nil ? 1 : 0)
    }
}

private struct SidebarGroupRow: View, Equatable {
    let sidebar: SidebarModel
    let groups: GroupsModel
    let group: NoteGroup
    let newNote: (NoteGroup.ID) -> Void

    nonisolated static func == (lhs: SidebarGroupRow, rhs: SidebarGroupRow) -> Bool {
        MainActor.assumeIsolated { lhs.group == rhs.group }
    }

    var body: some View {
        GroupHeader(groups: groups, group: group, newNote: newNote)
            .padding(.vertical, 2)
            .reorderable(group.id, in: sidebar.reorder, plan: { [groups, id = group.id] in groups.sidebarPlan(lifting: id) }, onClick: { [groups, id = group.id] _ in
                groups.toggle(id)
            })
    }
}

private struct SidebarNoteRow: View, Equatable {
    let sidebar: SidebarModel
    let groups: GroupsModel
    let note: NoteSummary
    let group: NoteGroup?
    let actions: NoteRowActions

    nonisolated static func == (lhs: SidebarNoteRow, rhs: SidebarNoteRow) -> Bool {
        MainActor.assumeIsolated { lhs.note == rhs.note && lhs.group == rhs.group }
    }

    var body: some View {
        GroupLane(reorder: sidebar.reorder, id: note.id, group: group) {
            NoteRow(note: note, state: sidebar.rowState(note.id), actions: actions)
                .padding(.vertical, 1)
                .reorderable(note.id, in: sidebar.reorder, plan: { [groups, id = note.id] in groups.sidebarPlan(lifting: id) }, onPress: {
                    actions.select(note.id)
                }, onClick: { count in
                    if count == 2 { actions.keep(note.id) }
                })
        }
        .id(note.id)
    }
}

private struct SidebarFileRow: View, Equatable {
    let sidebar: SidebarModel
    let groups: GroupsModel
    let note: NoteSummary
    let actions: NoteRowActions

    nonisolated static func == (lhs: SidebarFileRow, rhs: SidebarFileRow) -> Bool {
        MainActor.assumeIsolated { lhs.note == rhs.note }
    }

    var body: some View {
        NoteRow(note: note, state: sidebar.rowState(note.id), actions: actions)
            .padding(.vertical, 1)
            .reorderable(note.id, in: sidebar.fileReorder, plan: { [groups, id = note.id] in groups.filePlan(lifting: id) }, onPress: {
                actions.select(note.id)
            }, onClick: { count in
                if count == 2 { actions.keep(note.id) }
            })
            .id(note.id)
    }
}

/// Only this view follows the selection, so selecting a note does not rebuild the sidebar around it.
private struct SelectionScroller: View {
    let tabs: TabsModel
    let sidebar: SidebarModel
    let globalSearch: GlobalSearchModel
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear.onChange(of: tabs.selection) { _, id in
            guard let id, !globalSearch.isShown, !sidebar.isPressed else { return }
            proxy.scrollTo(id)
        }
    }
}

/// One drop target for the whole sidebar: a file dropped on a note's row opens just above it, anywhere else at the end.
private struct FileDrop: DropDelegate {
    nonisolated static let space = "sidebarRoot"
    let model: AppModel
    let listTop: ObservedState<CGFloat>

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        let position = info.location.y - listTop.value
        MainActor.assumeIsolated { model.openDropped(providers, at: model.fileDropIndex(at: position)) }
        return true
    }
}

/// Indents a group's notes; the lifted note follows the group it would drop into.
private struct GroupLane<Content: View>: View {
    let reorder: ReorderSession
    let id: Note.ID
    let group: NoteGroup?
    @ViewBuilder let content: Content

    var body: some View {
        let cell = reorder.cell(id)
        content
            .padding(.leading, isIndented(cell) ? 9 : 0)
            .anchorPreference(key: GroupBarKey.self, value: .bounds) { [GroupBarItem(id: id, group: group?.id, bounds: $0)] }
    }

    private func isIndented(_ cell: ReorderCell) -> Bool {
        guard cell.lift?.isAlone == true, let landing = reorder.landing else { return group != nil }
        return landing.lane != nil
    }
}

private struct GroupBarItem {
    let id: Note.ID
    let group: NoteGroup.ID?
    let bounds: Anchor<CGRect>
}

private struct GroupBarKey: PreferenceKey {
    static let defaultValue: [GroupBarItem] = []

    static func reduce(value: inout [GroupBarItem], nextValue: () -> [GroupBarItem]) {
        value += nextValue()
    }
}

/*
 One unbroken bar per open group, from its first note to its last, drawn over the list rather than per row so it
 never splits while rows slide. A note being dragged counts where it would land, so the bar spans the gap it leaves.
 */
private struct GroupBars: View {
    let reorder: ReorderSession
    let groups: GroupsModel
    let items: [GroupBarItem]
    let proxy: GeometryProxy

    private struct Span {
        let group: NoteGroup
        var x: CGFloat
        var top: CGFloat
        var bottom: CGFloat
    }

    var body: some View {
        ForEach(spans, id: \.group.id) { span in
            UnevenRoundedRectangle(bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5)
                .fill(span.group.color.color)
                .frame(width: 3, height: max(0, span.bottom - span.top))
                .position(x: span.x + 1.5, y: (span.top + span.bottom) / 2)
        }
    }

    private var spans: [Span] {
        let session = reorder
        var spans: [Span] = []
        for item in items {
            let placed: (group: NoteGroup.ID?, shift: CGFloat)
            if session.lifted == [item.id], let landing = session.landing {
                placed = (landing.lane, landing.offset)
            } else if session.lifted.contains(item.id) {
                placed = (item.group, session.translation)
            } else {
                placed = (item.group, session.shifts[item.id] ?? 0)
            }
            guard let id = placed.group, let group = groups.list.group(id), !group.isCollapsed else { continue }
            let rect = proxy[item.bounds]
            let top = rect.minY + placed.shift
            let bottom = rect.maxY + placed.shift - 2
            if let index = spans.firstIndex(where: { $0.group.id == group.id }) {
                spans[index].top = min(spans[index].top, top)
                spans[index].bottom = max(spans[index].bottom, bottom)
                spans[index].x = min(spans[index].x, rect.minX)
            } else {
                spans.append(Span(group: group, x: rect.minX, top: top, bottom: bottom))
            }
        }
        return spans
    }
}
