import HardydoNotesCore
import SwiftUI

struct FindBar: View {
    let model: AppModel
    @Bindable var find: FindModel
    @FocusState private var focus: Field?

    private enum Field {
        case query
        case replace
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button { model.find.showsReplace.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(model.find.showsReplace ? 90 : 0))
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.icon)
            .help("Toggle Replace (⌥⌘F)")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    box {
                        TextField("Find", text: Binding(get: { model.find.query }, set: { model.setFindQuery($0) }))
                            .focused($focus, equals: .query)
                            .onSubmit { model.findNext() }
                            .onKeyPress(.return, phases: .down) { press in
                                guard press.modifiers.contains(.shift) else { return .ignored }
                                model.findNext(forward: false)
                                return .handled
                            }
                        SearchOptionToggles(options: model.searchOptions) { model.setSearchOptions($0) }
                    }
                    Text(counter)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(counterColor)
                        .frame(minWidth: 58, alignment: .leading)
                    HStack(spacing: 0) {
                        iconButton("chevron.up", "Previous Match (⇧⌘G, ⇧↩)") { model.findNext(forward: false) }
                        iconButton("chevron.down", "Next Match (⌘G, ↩)") { model.findNext() }
                    }
                    .disabled(model.find.ranges.isEmpty)
                    Spacer(minLength: 0)
                    iconButton("xmark", "Close (Esc)") { model.closeFind() }
                }
                if model.find.showsReplace {
                    HStack(spacing: 6) {
                        box {
                            TextField(model.searchOptions.regex ? "Replace ($1, $2… refer to regex groups)" : "Replace", text: $find.replaceText)
                                .focused($focus, equals: .replace)
                                .onSubmit { model.replaceCurrent() }
                        }
                        Button("Replace") { model.replaceCurrent() }
                            .help("Replace this match and go to the next (↩ in the Replace field)")
                            .disabled(!model.canReplace)
                        Button("Replace All") { model.replaceAll() }
                            .help("Replace every match in the note (⌘Z to undo)")
                            .disabled(!model.canReplace)
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
        .onExitCommand { model.closeFind() }
        .onAppear { focus = .query }
        .onChange(of: model.find.focusRequest) { focus = .query }
        .task(id: model.findInputs) { await model.refreshFind() }
    }

    private var counter: String {
        let find = model.find
        if let error = find.error { return error }
        if find.ranges.isEmpty { return "No results" }
        let total = find.ranges.count >= TextSearch.maxMatches ? "\(find.ranges.count)+" : "\(find.ranges.count)"
        return find.currentIndex.map { "\($0 + 1) / \(total)" } ?? "\(total) \(find.ranges.count == 1 ? "result" : "results")"
    }

    private var counterColor: Color {
        let find = model.find
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
