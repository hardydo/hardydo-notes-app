import HardydoNotesCore
import SwiftUI

struct WorkspaceToolbar: ToolbarContent {
    @Bindable var model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if model.selection != nil {
                ModeSwitcher(mode: $model.viewMode)
                    .help("Editor ⌥⌘1 · Split ⌥⌘2 · Preview ⌥⌘3 · Toggle Preview ⇧⌘V")
                if model.viewMode == .split {
                    Button { model.toggleScrollSync() } label: { Image(systemName: "arrow.up.arrow.down") }
                        .buttonStyle(.toolbarToggle(isOn: model.isScrollSynced))
                        .help(model.isScrollSynced ? "Sync Scroll is on: the editor and the preview scroll together" : "Sync Scroll is off: scroll the editor and the preview separately")
                }
                if model.viewMode != .preview, model.selectedLanguage == .markdown {
                    FormatBar(editor: model.editor) { model.isInsertingTable = true }
                        .disabled(model.selectedNote?.isLocked == true)
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.selectedNote != nil, model.viewMode != .preview, model.selectedLanguage != .markdown {
                LanguageBadge(language: model.selectedLanguage)
            }
            if model.selectedLanguage == .json, model.selectedNote != nil {
                Button { model.formatDocument() } label: {
                    Label {
                        Text("Format").font(.system(size: 13))
                    } icon: {
                        Image(systemName: "text.alignleft")
                    }
                    .labelStyle(.titleAndIcon)
                }
                .disabled(!model.canFormatDocument)
                .buttonStyle(.toolbarIcon)
                .help(model.viewMode == .preview ? "Switch to Editor or Split to format JSON" : "Re-indent the JSON, keeping its order (⇧⌥F)")
            }
            if let note = model.selectedNote {
                Button { model.toggleLock() } label: {
                    Image(systemName: note.isLocked ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.toolbarIcon)
                .help(note.isLocked ? "This note is locked (read-only). Click to unlock (⌥⌘L)" : "Lock the note to make it read-only (⌥⌘L)")
            }
            Button { model.newNote() } label: { Image(systemName: "square.and.pencil") }
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
