import HardydoNotesCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @FocusState private var isListFocused: Bool
    @FocusState private var isSearchFocused: Bool

    // A plain stack instead of List: List's native highlight turns grey once the editor has focus, and its onMove never starts while rows handle taps.
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    Group {
                        if model.isSearchingAll {
                            GlobalSearchField(model: model, isFocused: $isSearchFocused)
                        } else {
                            header
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, geometry.safeAreaInsets.top + 6)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if model.isSearchingAll {
                                GlobalSearchResults(model: model)
                            } else {
                                list
                            }
                        }
                        .overlayPreferenceValue(GroupBarKey.self) { items in
                            GeometryReader { proxy in GroupBars(model: model, items: items, proxy: proxy) }
                                .allowsHitTesting(false)
                        }
                        .coordinateSpace(.named("sidebar"))
                        .background(ThinScrollBar())
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                }
                // The sidebar scroll view applies the toolbar inset twice on this macOS, leaving a gap; the toolbar height is padded in by hand instead.
                .ignoresSafeArea(.container, edges: .top)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    model.openDropped(providers, at: model.store.notes.count)
                    return true
                }
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
                    if model.visibleNotes.contains(where: { $0.id == model.selection }) { model.requestDelete(model.selection) }
                }
                .onChange(of: model.selection) { _, id in
                    if let id, !model.isSearchingAll { withAnimation { proxy.scrollTo(id) } }
                }
                .onChange(of: model.searchFocusRequest) { isSearchFocused = true }
                .onAppear {
                    if model.isSearchingAll { isSearchFocused = true }
                }
            }
        }
    }

    private var header: some View {
        // At one point size the solid magnifier and the tall trash look bigger than the open square of the pencil.
        SectionHeader(title: "Hardydo Notes") {
            Button { model.openGlobalSearch() } label: { Image(systemName: "magnifyingglass").font(.system(size: 12.5)) }
                .help("Search All Notes (⇧⌘F)")
            Button { model.isClearingEmptyNotes = true } label: { Image(systemName: "trash").font(.system(size: 12)) }
                .help("Delete Empty Notes…")
                .disabled(model.store.emptyNotes.isEmpty)
            Button { model.newNote() } label: { Image(systemName: "square.and.pencil") }
                .help("New Note (⌘N)")
        }
    }

    @ViewBuilder
    private var list: some View {
        let rows = model.groups.rows(for: model.store.appNotes)
        ForEach(rows) { row in
            switch row {
            case .header(let group):
                GroupHeader(model: model, group: group)
                    .padding(.vertical, 2)
                    .reorderable(group.id, in: model.sidebarReorder, plan: { model.sidebarPlan(lifting: group.id) }, onClick: { _ in
                        model.toggleGroup(group.id)
                    })
            case .note(let note, let group):
                GroupLane(model: model, id: note.id, group: group) {
                    noteRow(note)
                        .reorderable(note.id, in: model.sidebarReorder, plan: { model.sidebarPlan(lifting: note.id) }, onPress: {
                            actions.select(note.id)
                        }, onClick: { count in
                            if count == 2 { actions.keep(note.id) }
                        })
                }
                .id(note.id)
            }
        }
        let files = model.store.localFileNotes
        if !files.isEmpty {
            SectionHeader(title: "Open Files") { EmptyView() }
                .padding(.top, 8)
            ForEach(files) { note in
                noteRow(note)
                    .reorderable(note.id, in: model.fileReorder, plan: { model.filePlan(lifting: note.id) }, onPress: {
                        actions.select(note.id)
                    }, onClick: { count in
                        if count == 2 { actions.keep(note.id) }
                    })
                    .id(note.id)
            }
        }
    }

    private var actions: NoteRowActions {
        NoteRowActions(model: model) { isListFocused = true }
    }

    private func noteRow(_ note: Note) -> some View {
        NoteRow(note: note, isSelected: model.selection == note.id, actions: actions)
            .equatable()
            .padding(.vertical, 1)
    }
}

/// Indents a group's notes; the lifted note follows the group it would drop into.
private struct GroupLane<Content: View>: View {
    let model: AppModel
    let id: Note.ID
    let group: NoteGroup?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.leading, isIndented ? 9 : 0)
            .anchorPreference(key: GroupBarKey.self, value: .bounds) { [GroupBarItem(id: id, group: group?.id, bounds: $0)] }
            .zIndex(model.sidebarReorder.lifted.contains(id) ? 1 : 0)
    }

    private var isIndented: Bool {
        let session = model.sidebarReorder
        guard session.lifted == [id], let landing = session.landing else { return group != nil }
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
    let model: AppModel
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
        let session = model.sidebarReorder
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
            guard let id = placed.group, let group = model.groups.group(id), !group.isCollapsed else { continue }
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

/// What a row does, kept apart from what it shows so rows compare by their content alone.
@MainActor
struct NoteRowActions {
    let model: AppModel
    let focusList: () -> Void

    func select(_ id: Note.ID) {
        model.selectNote(id)
        focusList()
    }

    func keep(_ id: Note.ID) { model.keepTab(id) }
    func remove(_ id: Note.ID) { model.requestDelete(id) }

    func openFiles(_ providers: [NSItemProvider], at id: Note.ID) -> Bool {
        model.openDropped(providers, at: model.store.notes.firstIndex { $0.id == id } ?? 0)
        return true
    }
}

struct SectionHeader<Actions: View>: View {
    let title: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            actions
                .buttonStyle(.icon)
                .font(.system(size: 13.5))
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}
