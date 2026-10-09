import HardydoNotesCore
import SwiftUI

/// The search box that replaces the note list while searching all notes; it stays put while the results scroll.
struct GlobalSearchField: View {
    let model: AppModel
    @Bindable var search: GlobalSearchModel
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search all notes", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused(isFocused)
                    .onExitCommand { model.closeGlobalSearch() }
                SearchOptionToggles(options: model.find.options) { model.find.setOptions($0) }
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
                .foregroundStyle(search.error == nil ? Color.secondary : Color.red)
                .padding(.horizontal, 4)
        }
        .padding(.bottom, 8)
        // The field lives as long as the search, unlike the results, whose rows come and go as they scroll.
        .task(id: model.globalSearchInputs) { await model.runGlobalSearch() }
    }

    private var summary: String {
        if let error = search.error { return error }
        if search.query.isEmpty { return "Type to search the text of every note." }
        guard !search.results.isEmpty else { return "No results." }
        let matches = search.matchCount
        let notes = search.results.count
        return "\(matches) \(matches == 1 ? "result" : "results") in \(notes) \(notes == 1 ? "note" : "notes")"
    }
}

/// One row per note and per line, so the list only builds the rows that scroll into view.
/// Reads the selection and the find match itself, so the sidebar around it does not follow them.
struct GlobalSearchResults: View {
    let search: GlobalSearchModel
    let tabs: TabsModel
    let find: FindModel
    let open: (Note.ID, LineMatch) -> Void

    /*
     Notes and lines are identified by their place: every new query brings other notes and lines, and rows keyed
     by them were all torn down and built again; keyed by place, the rows already built take the new text.
     Lines are placed within their note, so folding one note leaves the rows of the others as they are.
     */
    var body: some View {
        let collapsed = search.collapsed
        ForEach(Array(search.results.enumerated()), id: \.offset) { place, result in
            let isCollapsed = collapsed.contains(result.id)
            ResultHeader(result: result, isCollapsed: isCollapsed) { toggle(result.id) }
            if !isCollapsed {
                ForEach(result.lines.indices.map { LinePlace(note: place, line: $0) }, id: \.self) { slot in
                    let line = result.lines[slot.line]
                    ResultLine(
                        line: line,
                        isCurrent: tabs.selection == result.id && find.current == line.range
                    ) { open(result.id, line) }
                        .padding(.top, 1)
                        .padding(.bottom, slot.line == result.lines.count - 1 ? 6 : 0)
                }
            }
        }
    }

    private struct LinePlace: Hashable {
        let note: Int
        let line: Int
    }

    private func toggle(_ id: Note.ID) {
        if search.collapsed.contains(id) {
            search.collapsed.remove(id)
        } else {
            search.collapsed.insert(id)
        }
    }
}

private struct ResultHeader: View {
    let result: NoteMatches
    let isCollapsed: Bool
    let toggle: () -> Void
    @StateObject private var hover = ViewState(false)

    var body: some View {
        Button(action: toggle) {
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
                Text(verbatim: result.isClipped ? "\(result.lines.count)+" : "\(result.lines.count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hover.value ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .pointerStyle(.link)
        .help(isCollapsed ? "Expand" : "Collapse")
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
                Text(verbatim: "\(line.line)")
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
