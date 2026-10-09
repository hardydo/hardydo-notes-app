import HardydoNotesCore
import Observation

enum QuickOpenMode: Equatable {
    case notes
    case line
}

@MainActor
@Observable
final class QuickOpenModel {
    private(set) var mode: QuickOpenMode?
    @ObservationIgnored private let editor: EditorController

    init(editor: EditorController) {
        self.editor = editor
    }

    func show(_ mode: QuickOpenMode = .notes) {
        editor.commit()
        self.mode = mode
    }

    /// Closes and gives the editor its focus back.
    func close() {
        mode = nil
        editor.focus()
    }

    /// Closes and leaves the focus where whatever closed the palette put it.
    func dismiss() {
        mode = nil
    }
}

struct QuickOpenActions {
    let notes: (String) -> [NoteSummary]
    let place: (NoteSummary) -> String?
    let lineCount: () -> Int
    let open: (Note.ID) -> Void
    let goToLine: (Int) -> Void
}
