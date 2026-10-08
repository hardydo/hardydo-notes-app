import HardydoNotesCore
import SwiftUI

/// VS Code's breadcrumbs: where the note lives, then the headings around the caret.
struct BreadcrumbBar: View {
    let model: AppModel
    let note: Note
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
        .onChange(of: note.body, initial: true) { outline.update(note.body, isMarkdown: language == .markdown) }
        .onChange(of: language) { outline.update(note.body, isMarkdown: language == .markdown) }
    }

    private var segments: [Segment] {
        var result: [Segment]
        if let file = note.localFile {
            let components = URL(fileURLWithPath: file.path).pathComponents.dropFirst()
            result = components.dropLast().map { Segment(text: $0) }
            result.append(Segment(icon: "doc", text: note.title))
        } else {
            result = [Segment(text: "Hardydo Notes")]
            if let group = model.groups.group(of: note.id) {
                result.append(Segment(text: group.displayName))
            }
            result.append(Segment(text: note.title))
        }
        for heading in outline.path(at: model.editor.caretLocation) {
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

/// Headings are found off the main thread whenever the stored text changes; moving the caret only looks them up.
@MainActor
private final class OutlineCache: ObservableObject {
    @Published private(set) var headings: [MarkdownHeading] = []
    private var lineStarts: [Int] = []
    private var source: String?
    private var task: Task<Void, Never>?

    func update(_ text: String, isMarkdown: Bool) {
        let text = isMarkdown ? text : ""
        guard text != source else { return }
        source = text
        task?.cancel()
        task = Task {
            let found = await Task.detached(priority: .userInitiated) {
                (CodeFolding.markdownHeadings(in: text), CodeFolding.lineStarts(text as NSString))
            }.value
            guard !Task.isCancelled else { return }
            lineStarts = found.1
            headings = found.0
        }
    }

    func path(at location: Int) -> [MarkdownHeading] {
        guard !headings.isEmpty else { return [] }
        return CodeFolding.headingPath(headings, toLine: CodeFolding.line(of: location, in: lineStarts))
    }
}
