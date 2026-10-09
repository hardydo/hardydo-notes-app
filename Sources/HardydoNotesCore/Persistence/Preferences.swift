import Foundation

/// The app's settings in UserDefaults. The keys are what earlier builds wrote, so changing one would lose that setting.
public struct Preferences: @unchecked Sendable {
    public enum Key {
        public static let zoom = "zoom"
        public static let splitRatio = "splitRatio"
        public static let scrollSync = "scrollSync"
        public static let openTabs = "openTabs"
        public static let pinnedTabs = "pinnedTabs"
        public static let activeTab = "activeTab"
        public static let tableRows = "tableRows"
        public static let tableColumns = "tableColumns"
        public static let exportFormat = "exportFormat"
    }

    public static let sandboxSuite = "com.hardydo.drivenotes.sandbox"

    public let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// A run on throwaway data keeps its settings apart too; nil means the app's own domain.
    public static func suiteName(environment: [String: String]) -> String? {
        environment[AppPaths.sandboxVariable] == nil ? nil : sandboxSuite
    }

    public static func forCurrentRun() -> Preferences {
        let suite = suiteName(environment: ProcessInfo.processInfo.environment)
        return Preferences(defaults: suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard)
    }

    public var zoom: Double? {
        get { positive(Key.zoom) }
        nonmutating set { defaults.set(newValue, forKey: Key.zoom) }
    }

    public var splitRatio: Double? {
        get { positive(Key.splitRatio) }
        nonmutating set { defaults.set(newValue, forKey: Key.splitRatio) }
    }

    public var isScrollSynced: Bool? {
        get { defaults.object(forKey: Key.scrollSync) == nil ? nil : defaults.bool(forKey: Key.scrollSync) }
        nonmutating set { defaults.set(newValue, forKey: Key.scrollSync) }
    }

    public var openTabs: [UUID] {
        get { ids(Key.openTabs) }
        nonmutating set { defaults.set(newValue.map(\.uuidString), forKey: Key.openTabs) }
    }

    public var pinnedTabs: [UUID] {
        get { ids(Key.pinnedTabs) }
        nonmutating set { defaults.set(newValue.map(\.uuidString), forKey: Key.pinnedTabs) }
    }

    public var activeTab: UUID? {
        get { defaults.string(forKey: Key.activeTab).flatMap(UUID.init) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: Key.activeTab) }
    }

    public var exportFormat: Int {
        get { defaults.integer(forKey: Key.exportFormat) }
        nonmutating set { defaults.set(newValue, forKey: Key.exportFormat) }
    }

    private func positive(_ key: String) -> Double? {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    private func ids(_ key: String) -> [UUID] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init)
    }
}
