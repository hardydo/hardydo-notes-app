import HardydoNotesCore
import SwiftUI

/// The search box that replaces the note list while searching all notes; it stays put while the results scroll.
struct GlobalSearchField: View {
    @Bindable var model: AppModel
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search all notes", text: $model.globalQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused(isFocused)
                    .onExitCommand { model.closeGlobalSearch() }
                SearchOptionToggles(options: model.findOptions) { model.setFindOptions($0) }
                Button { model.closeGlobalSearch() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.icon)
                .help("Close Search (Esc)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(model.globalSearchError == nil ? Color.secondary : Color.red)
                .padding(.horizontal, 4)
        }
        .padding(.bottom, 8)
    }

    private var summary: String {
        if let error = model.globalSearchError { return error }
        if model.globalQuery.isEmpty { return "Type to search the text of every note." }
        let results = model.globalResults
        guard !results.isEmpty else { return "No results." }
        let matches = model.globalMatchCount
        return "\(matches) \(matches == 1 ? "result" : "results") in \(results.count) \(results.count == 1 ? "note" : "notes")"
    }
}

struct GlobalSearchResults: View {
    let model: AppModel

    var body: some View {
        ForEach(model.globalResults) { result in
            let isCollapsed = model.collapsedResults.contains(result.id)
            VStack(alignment: .leading, spacing: 1) {
                Button { toggle(result.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .frame(width: 10)
                        Image(systemName: result.isFile ? "doc" : "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(result.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(result.isClipped ? "\(result.lines.count)+" : "\(result.lines.count)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(isCollapsed ? "Expand" : "Collapse")
                if !isCollapsed {
                    ForEach(result.lines, id: \.range.location) { line in
                        ResultLine(
                            line: line,
                            isCurrent: model.selection == result.id && model.findCurrent == line.range
                        ) { model.openResult(result.id, line) }
                    }
                }
            }
            .padding(.bottom, isCollapsed ? 0 : 6)
        }
    }

    private func toggle(_ id: Note.ID) {
        if model.collapsedResults.contains(id) {
            model.collapsedResults.remove(id)
        } else {
            model.collapsedResults.insert(id)
        }
    }
}

private struct ResultLine: View {
    let line: LineMatch
    let isCurrent: Bool
    let open: () -> Void
    @StateObject private var hover = ViewState(false)

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(line.line)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 22, alignment: .trailing)
                Text(snippet)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.22) : hover.value ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .pointerStyle(.link)
    }

    private var snippet: AttributedString {
        var before = AttributedString(line.before)
        before.foregroundColor = .secondary
        var matched = AttributedString(line.matched)
        matched.backgroundColor = Color.yellow.opacity(0.35)
        matched.font = .system(size: 12.5, weight: .semibold)
        var after = AttributedString(line.after)
        after.foregroundColor = .secondary
        return before + matched + after
    }
}
