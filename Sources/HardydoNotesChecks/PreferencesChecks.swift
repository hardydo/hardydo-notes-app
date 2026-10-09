import Foundation
import HardydoNotesCore

func runPreferencesChecks() {
    checkEqual(
        [Preferences.Key.zoom, Preferences.Key.splitRatio, Preferences.Key.scrollSync, Preferences.Key.openTabs, Preferences.Key.pinnedTabs,
         Preferences.Key.activeTab, Preferences.Key.tableRows, Preferences.Key.tableColumns, Preferences.Key.exportFormat],
        ["zoom", "splitRatio", "scrollSync", "openTabs", "pinnedTabs", "activeTab", "tableRows", "tableColumns", "exportFormat"],
        "preference keys stay what earlier builds wrote"
    )
    checkEqual(Preferences.suiteName(environment: [:]), nil, "a normal run uses the app's own settings")
    checkEqual(Preferences.suiteName(environment: [AppPaths.sandboxVariable: "/tmp/x"]), "com.hardydo.drivenotes.sandbox", "a sandboxed run keeps its settings apart")

    // A suite named by a path lives in that file, so the checks leave nothing behind in ~/Library/Preferences.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-preferences-checks-\(UUID().uuidString)")
    guard let defaults = UserDefaults(suiteName: file.path) else { return check(false, "preferences checks get a defaults suite") }
    defer {
        defaults.removePersistentDomain(forName: file.path)
        try? FileManager.default.removeItem(at: file.appendingPathExtension("plist"))
    }
    let preferences = Preferences(defaults: defaults)

    checkEqual(preferences.zoom, nil, "no saved zoom reads as none")
    checkEqual(preferences.isScrollSynced, nil, "no saved scroll sync reads as none")
    checkEqual(preferences.openTabs, [], "no saved tabs read as none")
    checkEqual(preferences.exportFormat, 0, "no saved export format reads as the first")

    let tabs = [UUID(), UUID()]
    preferences.zoom = 1.25
    preferences.splitRatio = 0.4
    preferences.isScrollSynced = false
    preferences.openTabs = tabs
    preferences.pinnedTabs = [tabs[1]]
    preferences.activeTab = tabs[0]
    preferences.exportFormat = 2
    checkEqual(preferences.zoom, 1.25, "zoom round-trips")
    checkEqual(preferences.splitRatio, 0.4, "split ratio round-trips")
    checkEqual(preferences.isScrollSynced, false, "a turned-off scroll sync stays off")
    checkEqual(preferences.openTabs, tabs, "open tabs round-trip in order")
    checkEqual(preferences.pinnedTabs, [tabs[1]], "pinned tabs round-trip")
    checkEqual(preferences.activeTab, tabs[0], "the active tab round-trips")
    checkEqual(preferences.exportFormat, 2, "the export format round-trips")
    checkEqual(defaults.stringArray(forKey: "openTabs"), tabs.map(\.uuidString), "tabs are stored as id strings, as before")

    preferences.activeTab = nil
    checkEqual(preferences.activeTab, nil, "clearing the active tab removes it")
    defaults.set(0, forKey: Preferences.Key.zoom)
    checkEqual(preferences.zoom, nil, "a zero zoom is ignored")
    defaults.set(["not-an-id", tabs[0].uuidString], forKey: Preferences.Key.openTabs)
    checkEqual(preferences.openTabs, [tabs[0]], "unreadable tab ids are skipped")
}
