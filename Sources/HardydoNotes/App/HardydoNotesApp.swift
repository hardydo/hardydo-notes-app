import AppKit
import HardydoNotesCore
import SwiftUI

@main
struct HardydoNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model: AppModel

    init() {
        model = AppModel(
            store: NoteStore(notesFile: NotesFile(url: AppPaths.notesFile)),
            groupsFile: JSONFile(url: AppPaths.groupsFile),
            preferences: Preferences.forCurrentRun()
        )
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 480)
                .onAppear {
                    model.start()
                    delegate.model = model
                }
        }
        // Without a title the automatic style shrinks to the compact bar; unified keeps the full height.
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }
    }
}
