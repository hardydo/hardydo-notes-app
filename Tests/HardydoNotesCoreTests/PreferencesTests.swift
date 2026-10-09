import Foundation
import HardydoNotesCore
import Testing

private struct ScratchDefaults {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("hardydo-preferences-checks-\(UUID().uuidString)")
    let defaults: UserDefaults
    let preferences: Preferences

    // A suite named by a path lives in that file, so the tests leave nothing behind in ~/Library/Preferences.
    init() throws {
        defaults = try #require(UserDefaults(suiteName: file.path), "preferences tests get a defaults suite")
        preferences = Preferences(defaults: defaults)
    }

    func discard() {
        defaults.removePersistentDomain(forName: file.path)
        try? FileManager.default.removeItem(at: file.appendingPathExtension("plist"))
    }
}

@Suite struct PreferencesTests {
    @Test func preferenceKeysStayWhatEarlierBuildsWrote() {
        #expect(
            [Preferences.Key.zoom, Preferences.Key.splitRatio, Preferences.Key.scrollSync, Preferences.Key.openTabs, Preferences.Key.pinnedTabs,
             Preferences.Key.activeTab, Preferences.Key.tableRows, Preferences.Key.tableColumns, Preferences.Key.exportFormat]
            == ["zoom", "splitRatio", "scrollSync", "openTabs", "pinnedTabs", "activeTab", "tableRows", "tableColumns", "exportFormat"],
            "preference keys stay what earlier builds wrote"
        )
    }

    @Test func sandboxedRunsKeepTheirSettingsApart() {
        #expect(Preferences.suiteName(environment: [:]) == nil, "a normal run uses the app's own settings")
        #expect(Preferences.suiteName(environment: [AppPaths.sandboxVariable: "/tmp/x"]) == "com.hardydo.drivenotes.sandbox", "a sandboxed run keeps its settings apart")
    }

    @Test func unsetPreferencesReadAsNone() throws {
        let scratch = try ScratchDefaults()
        defer { scratch.discard() }
        let preferences = scratch.preferences
        #expect(preferences.zoom == nil, "no saved zoom reads as none")
        #expect(preferences.isScrollSynced == nil, "no saved scroll sync reads as none")
        #expect(preferences.openTabs == [], "no saved tabs read as none")
        #expect(preferences.exportFormat == 0, "no saved export format reads as the first")
    }

    @Test func preferencesRoundTrip() throws {
        let scratch = try ScratchDefaults()
        defer { scratch.discard() }
        let preferences = scratch.preferences
        let tabs = [UUID(), UUID()]
        preferences.zoom = 1.25
        preferences.splitRatio = 0.4
        preferences.isScrollSynced = false
        preferences.openTabs = tabs
        preferences.pinnedTabs = [tabs[1]]
        preferences.activeTab = tabs[0]
        preferences.exportFormat = 2
        #expect(preferences.zoom == 1.25, "zoom round-trips")
        #expect(preferences.splitRatio == 0.4, "split ratio round-trips")
        #expect(preferences.isScrollSynced == false, "a turned-off scroll sync stays off")
        #expect(preferences.openTabs == tabs, "open tabs round-trip in order")
        #expect(preferences.pinnedTabs == [tabs[1]], "pinned tabs round-trip")
        #expect(preferences.activeTab == tabs[0], "the active tab round-trips")
        #expect(preferences.exportFormat == 2, "the export format round-trips")
        #expect(scratch.defaults.stringArray(forKey: "openTabs") == tabs.map(\.uuidString), "tabs are stored as id strings, as before")
    }

    @Test func clearedAndUnreadableValuesAreIgnored() throws {
        let scratch = try ScratchDefaults()
        defer { scratch.discard() }
        let preferences = scratch.preferences
        let tab = UUID()
        preferences.activeTab = tab
        preferences.activeTab = nil
        #expect(preferences.activeTab == nil, "clearing the active tab removes it")
        scratch.defaults.set(0, forKey: Preferences.Key.zoom)
        #expect(preferences.zoom == nil, "a zero zoom is ignored")
        scratch.defaults.set(["not-an-id", tab.uuidString], forKey: Preferences.Key.openTabs)
        #expect(preferences.openTabs == [tab], "unreadable tab ids are skipped")
    }
}
