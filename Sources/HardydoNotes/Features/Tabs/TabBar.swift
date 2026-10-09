import HardydoNotesCore
import SwiftUI

struct TabBar: View {
    let model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabList.ids, id: \.self) { id in
                        if let note = model.store.note(id)?.summary {
                            TabItem(
                                note: note,
                                isActive: model.selection == id,
                                isTransient: model.transientTab == id,
                                isPinned: model.isTabPinned(id),
                                model: model
                            )
                            .equatable()
                            .reorderable(id, in: model.tabReorder, cornerRadius: 6, liftedFill: Color(nsColor: .textBackgroundColor), plan: { model.tabPlan(lifting: id) }, onPress: {
                                model.activate(id)
                            }, onClick: { count in
                                if count == 2 { model.keepTab(id) }
                            })
                            .id(id)
                        }
                    }
                }
                .coordinateSpace(.named("tabs"))
            }
            .onChange(of: model.selection) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One tab. Pinned tabs show a pin where others show ✕, and they ignore ⌘W and the middle button, as in VS Code.
private struct TabItem: View, Equatable {
    let note: NoteSummary
    let isActive: Bool
    let isTransient: Bool
    let isPinned: Bool
    let model: AppModel
    @StateObject private var hover = ViewState(false)

    private var isHovered: Bool { hover.value }

    nonisolated static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        MainActor.assumeIsolated {
            lhs.note.title == rhs.note.title && lhs.note.filePath == rhs.note.filePath
                && lhs.isActive == rhs.isActive && lhs.isTransient == rhs.isTransient && lhs.isPinned == rhs.isPinned
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if note.filePath != nil {
                Image(systemName: "doc")
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .help(note.filePath ?? "")
            }
            Text(note.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .italic(isTransient)
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            if isPinned {
                Button { model.setTabPinned(note.id, false) } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .rotationEffect(.degrees(45))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.icon)
                .help("Unpin Tab")
            } else {
                ZStack {
                    if isActive || isHovered {
                        HoverCloseButton(size: 16, help: "Close Tab (⌘W)") {
                            model.closeTab(note.id)
                        }
                    }
                }
                .frame(width: 16, height: 16)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: 220, minHeight: 34, maxHeight: 34)
        .background(isActive ? Color(nsColor: .textBackgroundColor) : isHovered ? Color.primary.opacity(0.04) : .clear, ignoresSafeAreaEdges: [])
        .overlay(alignment: .top) {
            if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
        }
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { inside in
            hover.value = inside
            if inside {
                model.tabUnderPointer = note.id
            } else if model.tabUnderPointer == note.id {
                model.tabUnderPointer = nil
            }
        }
        .help(note.filePath ?? note.title)
        .contextMenu { TabContextMenu(model: model, id: note.id, isTransient: isTransient, isPinned: isPinned) }
    }
}

private struct TabContextMenu: View {
    let model: AppModel
    let id: Note.ID
    let isTransient: Bool
    let isPinned: Bool

    var body: some View {
        Button(isPinned ? "Unpin Tab" : "Pin Tab") { model.setTabPinned(id, !isPinned) }
        if isTransient {
            Button("Keep Tab Open") { model.keepTab(id) }
        }
        if let note = model.store.note(id)?.summary {
            Button(note.isLocked ? "Unlock" : "Lock (Read-Only)") { model.setLocked(id, !note.isLocked) }
            if note.filePath == nil {
                Button("Rename…") { model.requestRename(id) }
                    .disabled(note.isLocked)
            }
        }
        Divider()
        Button("Close Tab") { model.closeTab(id) }
        Button("Close Other Tabs") { model.closeOtherTabs(id) }
            .disabled(!model.tabList.canCloseOthers(id))
        Button("Close Tabs to the Right") { model.closeTabs(rightOf: id) }
            .disabled(!model.tabList.canCloseRight(of: id))
        Button("Close All Tabs") { model.closeAllTabs() }
            .disabled(!model.tabList.canCloseAll)
        Divider()
        Button("Reopen Closed Tab") { model.reopenClosedTab() }
            .disabled(!model.tabList.canReopen)
    }
}
