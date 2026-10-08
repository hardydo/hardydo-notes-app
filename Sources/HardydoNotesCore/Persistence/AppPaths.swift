import Foundation

/// Where the app keeps its data: notes and groups in Application Support, window and tab state in UserDefaults.
public enum AppPaths {
    public static let folderName = "com.hardydo.drivenotes"

    public static var support: URL {
        applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    public static var notesFile: URL { support.appendingPathComponent("notes.json") }
    public static var groupsFile: URL { support.appendingPathComponent("groups.json") }

    /// Set to a folder to run against throwaway data, for development, instead of the real library.
    public static let sandboxVariable = "HARDYDO_NOTES_DATA"

    static var applicationSupport: URL {
        if let sandbox = ProcessInfo.processInfo.environment[sandboxVariable] { return URL(fileURLWithPath: sandbox, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Preferences for the same run: the app's own domain, or one kept apart with the throwaway data.
    public static var defaults: UserDefaults {
        guard ProcessInfo.processInfo.environment[sandboxVariable] != nil else { return .standard }
        return UserDefaults(suiteName: "com.hardydo.drivenotes.sandbox") ?? .standard
    }
}
