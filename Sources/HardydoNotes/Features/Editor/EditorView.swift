import AppKit
import HardydoNotesCore
import SwiftUI

struct EditorView: NSViewRepresentable {
    /// The editor replaces its own text only when the revision moves past the one it last synced.
    let text: NoteText
    let language: ContentLanguage
    let isEditable: Bool
    let zoom: CGFloat
    var highlights: [NSRange] = []
    var currentHighlight: NSRange?
    let controller: EditorController
    var onEscape: () -> Bool = { false }
    var onEdit: () -> Void = {}
    /// Hands typed text to the store; returns the new revision, or nil when the store kept its text.
    let onChange: (String) -> Int?

    func makeNSView(context: Context) -> EditorHost {
        EditorHost()
    }

    func updateNSView(_ host: EditorHost, context: Context) {
        let session = controller.session(for: text.note) {
            EditorSession(text: text, language: language, isEditable: isEditable, zoom: zoom, controller: controller)
        }
        session.onChange = onChange
        session.onEdit = onEdit
        session.onEscape = onEscape
        if host.session !== session {
            let hadFocus = host.session.map { host.window?.firstResponder === $0.textView } ?? false
            host.session?.commit()
            host.show(session)
            if hadFocus || session.wantsFocus {
                DispatchQueue.main.async { session.textView.window?.makeFirstResponder(session.textView) }
            }
        }
        if controller.textView !== session.textView { controller.attach(session.textView, commit: session.commit) }
        session.update(text: text, language: language, isEditable: isEditable, zoom: zoom, highlights: highlights, currentHighlight: currentHighlight)
        if let range = controller.pendingReveal, NSMaxRange(range) <= (session.textView.textStorage?.length ?? 0) {
            controller.pendingReveal = nil
            let controller = controller
            DispatchQueue.main.async { controller.reveal(range) }
        }
    }

    static func dismantleNSView(_ host: EditorHost, coordinator: ()) {
        guard let session = host.session else { return }
        session.commit()
        session.controller?.detach(session.textView)
    }
}

/// Holds the scroll view of the session on show; the sessions themselves live in the editor controller.
final class EditorHost: NSView {
    private(set) var session: EditorSession?

    func show(_ next: EditorSession) {
        session?.scrollView.removeFromSuperview()
        session = next
        next.scrollView.frame = bounds
        next.scrollView.autoresizingMask = [.width, .height]
        addSubview(next.scrollView)
    }
}
