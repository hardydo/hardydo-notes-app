import HardydoNotesCore
import SwiftUI

/*
 The toolbar itself never reads the open note: SwiftUI rebuilds every NSToolbarItem whenever this content
 changes, so the parts that follow the note live in the two views below and update on their own.
 */
struct WorkspaceToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) { PrincipalTools(workspace: model.workspace, layout: model.layout) }
        ToolbarItem(placement: .primaryAction) { ActionTools(workspace: model.workspace, newNote: model.newNote).equatable() }
    }
}

private struct PrincipalTools: View {
    @Bindable var workspace: WorkspaceEditor
    let layout: LayoutSettings

    var body: some View {
        HStack(spacing: 10) {
            if workspace.hasNote {
                ModeSwitcher(mode: $workspace.viewMode)
                    .help("Editor ⌥⌘1 · Split ⌥⌘2 · Preview ⌥⌘3 · Toggle Preview ⇧⌘V")
                if workspace.viewMode == .split {
                    Button { workspace.toggleScrollSync() } label: { Image(systemName: "arrow.up.arrow.down") }
                        .buttonStyle(.toolbarToggle(isOn: layout.isScrollSynced))
                        .help(layout.isScrollSynced ? "Sync Scroll is on: the editor and the preview scroll together" : "Sync Scroll is off: scroll the editor and the preview separately")
                }
                if workspace.viewMode != .preview, workspace.language == .markdown {
                    FormatBar(editor: workspace.controller) { workspace.isInsertingTable = true }
                        .disabled(workspace.note?.isLocked == true)
                }
            }
        }
    }
}

private struct ActionTools: View, Equatable {
    let workspace: WorkspaceEditor
    let newNote: () -> Void

    // The closures are made anew on every render of the parent, but always act on the same models, so those are compared.
    nonisolated static func == (lhs: ActionTools, rhs: ActionTools) -> Bool {
        MainActor.assumeIsolated { lhs.workspace === rhs.workspace }
    }

    var body: some View {
        HStack(spacing: 8) {
            if workspace.note != nil, workspace.viewMode != .preview, workspace.language != .markdown {
                LanguageBadge(language: workspace.language)
            }
            if workspace.language == .json, workspace.note != nil {
                Button { workspace.formatDocument() } label: {
                    Label {
                        Text("Format").font(.system(size: 13))
                    } icon: {
                        Image(systemName: "text.alignleft")
                    }
                    .labelStyle(.titleAndIcon)
                }
                .disabled(!workspace.canFormatDocument)
                .buttonStyle(.toolbarIcon)
                .help(workspace.viewMode == .preview ? "Switch to Editor or Split to format JSON" : "Re-indent the JSON, keeping its order (⇧⌥F)")
            }
            if let isLocked = workspace.note?.isLocked {
                Button { workspace.toggleLock() } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.toolbarIcon)
                .help(isLocked ? "This note is locked (read-only). Click to unlock (⌥⌘L)" : "Lock the note to make it read-only (⌥⌘L)")
            }
            Button { newNote() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.toolbarIcon)
                .help("New Note (⌘N)")
        }
    }
}

/// For code notes the Markdown buttons do not apply, so the toolbar names the language instead.
private struct LanguageBadge: View {
    let language: ContentLanguage

    var body: some View {
        Text(language.name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .help("Detected content type")
    }
}
