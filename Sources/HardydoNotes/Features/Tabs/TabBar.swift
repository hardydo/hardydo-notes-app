import HardydoNotesCore
import SwiftUI

struct TabBar: View, Equatable {
    let tabs: TabsModel
    let actions: TabActions
    @StateObject private var width = ViewState(CGFloat(0))

    // The closures are made anew on every render of the parent, but always act on the same models, so those are compared.
    nonisolated static func == (lhs: TabBar, rhs: TabBar) -> Bool {
        MainActor.assumeIsolated { lhs.tabs === rhs.tabs }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.list.ids, id: \.self) { id in
                        if let note = actions.note(id) {
                            TabItem(
                                note: note,
                                isActive: tabs.selection == id,
                                isTransient: tabs.transient == id,
                                isPinned: tabs.isPinned(id),
                                tabs: tabs,
                                actions: actions
                            )
                            .equatable()
                            .reorderable(id, in: tabs.reorder, cornerRadius: 6, liftedFill: Color(nsColor: .textBackgroundColor), plan: { tabs.plan(lifting: id) }, onPress: {
                                tabs.activate(id)
                            }, onClick: { count in
                                if count == 2 { tabs.keep(id) }
                            })
                            .id(id)
                        }
                    }
                }
                .coordinateSpace(.named("tabs"))
                .fixedSize(horizontal: true, vertical: false)
                // As in VS Code, a double click on the bar beside the tabs opens a new note.
                .frame(minWidth: width.value, alignment: .leading)
                .background(Color.clear.contentShape(Rectangle()).onTapGesture(count: 2) { actions.newNote() })
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.value = $0 }
            .onChange(of: tabs.selection) { _, id in
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
    let tabs: TabsModel
    let actions: TabActions
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
                Button { tabs.setPinned(note.id, false) } label: {
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
                            tabs.close(note.id)
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
                tabs.underPointer = note.id
            } else if tabs.underPointer == note.id {
                tabs.underPointer = nil
            }
        }
        .help(note.filePath ?? note.title)
        .contextMenu { TabContextMenu(tabs: tabs, actions: actions, id: note.id, isTransient: isTransient, isPinned: isPinned) }
    }
}

private struct TabContextMenu: View {
    let tabs: TabsModel
    let actions: TabActions
    let id: Note.ID
    let isTransient: Bool
    let isPinned: Bool

    var body: some View {
        Button(isPinned ? "Unpin Tab" : "Pin Tab") { tabs.setPinned(id, !isPinned) }
        if isTransient {
            Button("Keep Tab Open") { tabs.keep(id) }
        }
        if let note = actions.note(id) {
            Button(note.isLocked ? "Unlock" : "Lock (Read-Only)") { actions.setLocked(id, !note.isLocked) }
            if note.filePath == nil {
                Button("Rename…") { actions.rename(id) }
                    .disabled(note.isLocked)
            }
        }
        Divider()
        Button("Close Tab") { tabs.close(id) }
        Button("Close Other Tabs") { tabs.closeOthers(id) }
            .disabled(!tabs.list.canCloseOthers(id))
        Button("Close Tabs to the Right") { tabs.closeRight(of: id) }
            .disabled(!tabs.list.canCloseRight(of: id))
        Button("Close All Tabs") { tabs.closeAll() }
            .disabled(!tabs.list.canCloseAll)
        Divider()
        Button("Reopen Closed Tab") { tabs.reopen() }
            .disabled(!tabs.list.canReopen)
    }
}
