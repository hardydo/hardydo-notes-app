import HardydoNotesCore
import SwiftUI

/// VS Code's breadcrumbs: where the note lives, then the headings around the caret.
struct BreadcrumbBar: View {
    let workspace: WorkspaceEditor
    let groups: GroupsModel
    let note: NoteSummary
    let revision: Int
    let language: ContentLanguage
    @StateObject private var outline = OutlineCache()

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 4) {
                        if let icon = segment.icon {
                            Image(systemName: icon)
                                .font(.system(size: 10.5))
                                .foregroundStyle(segment.isHeading ? Color.yellow.opacity(0.85) : Color.accentColor)
                        }
                        Text(segment.text)
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.leading, for: .alignment)
        .defaultScrollAnchor(.trailing, for: .initialOffset)
        .defaultScrollAnchor(.trailing, for: .sizeChanges)
        .frame(height: 24)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: OutlineSource(note: note.id, revision: revision, isMarkdown: language == .markdown), initial: true) { _, source in
            outline.update(source) { workspace.note?.body ?? "" }
        }
    }

    private var segments: [Segment] {
        var result: [Segment]
        if let path = note.filePath {
            let components = URL(fileURLWithPath: path).pathComponents.dropFirst()
            result = components.dropLast().map { Segment(text: $0) }
            result.append(Segment(icon: "doc", text: note.title))
        } else {
            result = [Segment(text: AppInfo.name)]
            if let group = groups.list.group(of: note.id) {
                result.append(Segment(text: group.displayName))
            }
            result.append(Segment(text: note.title))
        }
        for heading in outline.path(atLine: workspace.controller.caretLine) {
            result.append(Segment(icon: "textformat.abc", text: String(repeating: "#", count: heading.level) + " " + heading.title, isHeading: true))
        }
        return result
    }
}

private struct Segment {
    var icon: String?
    let text: String
    var isHeading = false
}

private struct OutlineSource: Equatable {
    let note: Note.ID
    let revision: Int
    let isMarkdown: Bool
}

/// Headings are found off the main thread whenever the stored text changes; moving the caret only looks them up.
@MainActor
private final class OutlineCache: ObservableObject {
    @Published private(set) var headings: [MarkdownHeading] = []
    private var source: OutlineSource?
    private var task: Task<Void, Never>?

    func update(_ source: OutlineSource, text: () -> String) {
        guard source != self.source else { return }
        self.source = source
        let text = source.isMarkdown ? text() : ""
        task?.cancel()
        task = Task {
            let found = await Task.detached(priority: .userInitiated) { MarkdownOutline.headings(in: text) }.value
            guard !Task.isCancelled else { return }
            headings = found
        }
    }

    func path(atLine line: Int) -> [MarkdownHeading] {
        guard !headings.isEmpty else { return [] }
        return MarkdownOutline.path(headings, toLine: line)
    }
}
