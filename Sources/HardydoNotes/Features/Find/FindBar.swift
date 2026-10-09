import HardydoNotesCore
import SwiftUI

struct FindBar: View {
    @Bindable var find: FindModel
    @FocusState private var focus: Field?

    private enum Field {
        case query
        case replace
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button { find.showsReplace.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(find.showsReplace ? 90 : 0))
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.icon)
            .help("Toggle Replace (⌥⌘F)")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    box {
                        TextField("Find", text: Binding(get: { find.query }, set: { find.setQuery($0) }))
                            .focused($focus, equals: .query)
                            .onSubmit { find.next() }
                            .onKeyPress(.return, phases: .down) { press in
                                guard press.modifiers.contains(.shift) else { return .ignored }
                                find.next(forward: false)
                                return .handled
                            }
                        SearchOptionToggles(options: find.options) { find.setOptions($0) }
                    }
                    Text(counter)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(counterColor)
                        .frame(minWidth: 58, alignment: .leading)
                    HStack(spacing: 0) {
                        iconButton("chevron.up", "Previous Match (⇧⌘G, ⇧↩)") { find.next(forward: false) }
                        iconButton("chevron.down", "Next Match (⌘G, ↩)") { find.next() }
                    }
                    .disabled(find.ranges.isEmpty)
                    Spacer(minLength: 0)
                    iconButton("xmark", "Close (Esc)") { find.close() }
                }
                if find.showsReplace {
                    HStack(spacing: 6) {
                        box {
                            TextField(find.options.regex ? "Replace ($1, $2… refer to regex groups)" : "Replace", text: $find.replaceText)
                                .focused($focus, equals: .replace)
                                .onSubmit { find.replaceCurrent() }
                        }
                        Button("Replace") { find.replaceCurrent() }
                            .help("Replace this match and go to the next (↩ in the Replace field)")
                            .disabled(!find.canReplace)
                        Button("Replace All") { find.replaceAll() }
                            .help("Replace every match in the note (⌘Z to undo)")
                            .disabled(!find.canReplace)
                        Spacer(minLength: 0)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand { find.close() }
        .onAppear { focus = .query }
        .onChange(of: find.focusRequest) { focus = .query }
        .task(id: find.inputs) {
            try? await Task.sleep(for: FindModel.typingPause)
            guard !Task.isCancelled else { return }
            await find.refresh()
        }
    }

    private var counter: String {
        if let error = find.error { return error }
        if find.ranges.isEmpty { return "No results" }
        let total = find.ranges.count >= TextSearch.maxMatches ? "\(find.ranges.count)+" : "\(find.ranges.count)"
        return find.currentIndex.map { "\($0 + 1) / \(total)" } ?? "\(total) \(find.ranges.count == 1 ? "result" : "results")"
    }

    private var counterColor: Color {
        if find.error != nil || (find.ranges.isEmpty && !find.query.isEmpty) { return .red }
        return find.query.isEmpty ? .primary : .secondary
    }

    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 24)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func iconButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.icon)
        .help(help)
    }
}
