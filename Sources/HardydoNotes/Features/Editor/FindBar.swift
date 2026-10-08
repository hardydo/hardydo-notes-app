import HardydoNotesCore
import SwiftUI

struct FindBar: View {
    @Bindable var model: AppModel
    @FocusState private var focus: Field?

    private enum Field {
        case query
        case replace
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button { model.showReplace.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(model.showReplace ? 90 : 0))
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.icon)
            .help("Toggle Replace (⌥⌘F)")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    box {
                        TextField("Find", text: Binding(get: { model.findQuery }, set: { model.setFindQuery($0) }))
                            .focused($focus, equals: .query)
                            .onSubmit { model.findNext() }
                            .onKeyPress(.return, phases: .down) { press in
                                guard press.modifiers.contains(.shift) else { return .ignored }
                                model.findNext(forward: false)
                                return .handled
                            }
                        SearchOptionToggles(options: model.findOptions) { model.setFindOptions($0) }
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
                    .disabled(model.findResult.ranges.isEmpty)
                    Spacer(minLength: 0)
                    iconButton("xmark", "Close (Esc)") { model.closeFind() }
                }
                if model.showReplace {
                    HStack(spacing: 6) {
                        box {
                            TextField(model.findOptions.regex ? "Replace ($1, $2… refer to regex groups)" : "Replace", text: $model.replaceText)
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
        .onChange(of: model.findFocusRequest) { focus = .query }
    }

    private var counter: String {
        let result = model.findResult
        if let error = result.error { return error }
        if result.ranges.isEmpty { return "No results" }
        let total = result.ranges.count >= TextSearch.maxMatches ? "\(result.ranges.count)+" : "\(result.ranges.count)"
        return model.findCurrentIndex.map { "\($0 + 1) / \(total)" } ?? "\(total) \(result.ranges.count == 1 ? "result" : "results")"
    }

    private var counterColor: Color {
        let result = model.findResult
        if result.error != nil || (result.ranges.isEmpty && !model.findQuery.isEmpty) { return .red }
        return model.findQuery.isEmpty ? .primary : .secondary
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
