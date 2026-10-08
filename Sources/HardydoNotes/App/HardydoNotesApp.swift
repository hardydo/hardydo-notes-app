import AppKit
import HardydoNotesCore
import SwiftUI

@main
struct HardydoNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model: AppModel

    init() {
        model = AppModel(
            store: NoteStore(cache: NoteCache(url: AppPaths.notesFile)),
            groupsFile: JSONFile(url: AppPaths.groupsFile),
            defaults: AppPaths.defaults
        )
    }

    var body: some Scene {
        Window("Hardydo Notes", id: "main") {
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? {
        didSet { openPendingFiles() }
    }
    private var pendingFiles: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingFiles += urls
        openPendingFiles()
    }

    private func openPendingFiles() {
        guard let model, !pendingFiles.isEmpty else { return }
        model.open(pendingFiles)
        pendingFiles = []
    }

    func applicationWillResignActive(_ notification: Notification) {
        model?.editor.commit()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let problem = model?.flushAll() else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Your Latest Changes Weren’t Saved"
        alert.informativeText = problem + "\n\nQuitting now loses them."
        alert.addButton(withTitle: "Don’t Quit")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
