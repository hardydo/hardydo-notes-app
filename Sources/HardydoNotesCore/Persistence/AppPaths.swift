import Foundation

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
}
