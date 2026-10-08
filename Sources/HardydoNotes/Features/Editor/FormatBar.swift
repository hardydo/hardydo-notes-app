import SwiftUI

struct FormatBar: View {
    let editor: EditorController
    let insertTable: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(1...3, id: \.self) { level in
                    Button("Heading \(level)") { editor.perform(.line(.heading(level))) }
                }
            } label: {
                menuLabel("textformat.size")
            }
            .help("Heading (⌘1, ⌘2, ⌘3)")
            button("Bold (⌘B)", "bold", .wrap("**"))
            button("Italic (⌘I)", "italic", .wrap("*"))
            button("Strikethrough (⇧⌘X)", "strikethrough", .wrap("~~"))
            button("Inline Code (⌘E)", "chevron.left.forwardslash.chevron.right", .wrap("`"))
            button("Bulleted List (⇧⌘8)", "list.bullet", .line(.bullet))
            button("Numbered List (⇧⌘7)", "list.number", .line(.numbered))
            button("Checklist (⇧⌘L)", "checklist", .line(.task))
            button("Quote (⇧⌘.)", "text.quote", .line(.quote))
            button("Link (⌘K)", "link", .link)
            Menu {
                Button("Table… (⌥⌘T)", action: insertTable)
                Button("Horizontal Rule (⌥⌘-)") { editor.perform(.rule) }
            } label: {
                menuLabel("tablecells")
            }
            .help("Insert a table or a horizontal rule")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.toolbarIcon)
    }

    private func button(_ help: String, _ icon: String, _ action: FormatAction) -> some View {
        Button { editor.perform(action) } label: { Image(systemName: icon) }
            .help(help)
    }

    private func menuLabel(_ icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
    }
}
