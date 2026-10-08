import HardydoNotesCore
import SwiftUI

/// A group's header pill, like an Edge tab group; a click folds the group, a drag moves the whole group.
struct GroupHeader: View {
    let model: AppModel
    let group: NoteGroup

    private var isEditing: Binding<Bool> {
        Binding(
            get: { model.editingGroup == group.id },
            set: { if !$0, model.editingGroup == group.id { model.editingGroup = nil } }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 7))
                    .rotationEffect(.degrees(group.isCollapsed ? -90 : 0))
                Text(group.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(group.color.color))
            .help(group.isCollapsed ? "Expand Group" : "Collapse Group")
            Spacer(minLength: 4)
            if group.isPinned {
                Image(systemName: "pin.fill")
                    .rotationEffect(.degrees(45))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Group pinned to the top")
            }
            Button { model.newNote(inGroup: group.id) } label: { Image(systemName: "plus") }
                .buttonStyle(.icon)
                .help("New Note in Group")
            Button { model.editingGroup = group.id } label: { Image(systemName: "pencil") }
                .buttonStyle(.icon)
                .help("Rename or Recolor Group")
                .popover(isPresented: isEditing, arrowEdge: .trailing) {
                    GroupEditor(model: model, group: group)
                }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.leading, 2)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("New Note in Group") { model.newNote(inGroup: group.id) }
            Button("Rename or Recolor…") { model.editingGroup = group.id }
            Button(group.isPinned ? "Unpin Group" : "Pin Group to Top") { model.setGroupPinned(group.id, !group.isPinned) }
            Divider()
            Button("Ungroup") { model.ungroup(group.id) }
        }
    }
}

struct GroupEditor: View {
    let model: AppModel
    let group: NoteGroup
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Group Name", text: Binding(get: { group.name }, set: { model.renameGroup(group.id, $0) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($isNameFocused)
                .onSubmit { model.editingGroup = nil }
            HStack(spacing: 4) {
                ForEach(GroupColor.allCases, id: \.self) { color in
                    Button { model.setGroupColor(group.id, color) } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(Circle().strokeBorder(color == group.color ? color.color : .clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(color.label)
                }
            }
            Divider()
            menuButton("plus", "New Note in Group") {
                model.editingGroup = nil
                model.newNote(inGroup: group.id)
            }
            menuButton(group.isPinned ? "pin.slash" : "pin", group.isPinned ? "Unpin Group" : "Pin Group to Top") {
                model.setGroupPinned(group.id, !group.isPinned)
            }
            menuButton("square.dashed", "Ungroup") { model.ungroup(group.id) }
        }
        .frame(width: 270)
        .padding(14)
        // The popover is not key yet when it appears, so the name field is focused on the next turn of the run loop.
        .onAppear { DispatchQueue.main.async { isNameFocused = true } }
    }

    private func menuButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

extension NoteGroup {
    var displayName: String { name.isEmpty ? "Group" : name }
}
