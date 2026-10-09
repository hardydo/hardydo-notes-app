import HardydoNotesCore
import Observation

struct AppAlert {
    let title: String
    let message: String
}

@MainActor
@Observable
final class DialogModel {
    var pendingDelete: Note.ID?
    var pendingRename: Note.ID?
    var renameText = ""
    var isClearingEmptyNotes = false
    var alert: AppAlert?

    func showAlert(_ title: String, _ message: String) {
        alert = AppAlert(title: title, message: message)
    }
}
