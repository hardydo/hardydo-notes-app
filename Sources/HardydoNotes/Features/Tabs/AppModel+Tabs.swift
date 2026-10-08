import AppKit
import HardydoNotesCore

extension AppModel {
    private static let tabsKey = "openTabs"
    private static let pinnedTabsKey = "pinnedTabs"
    private static let activeTabKey = "activeTab"

    var selection: Note.ID? { tabList.active }
    var previewTab: Note.ID? { tabList.preview }

    var tabs: [Note] {
        tabList.ids.compactMap(store.note)
    }

    func changeTabs(_ change: (inout TabList) -> Void) {
        let before = tabList.active
        var updated = tabList
        change(&updated)
        guard updated != tabList else { return }
        if updated.active != before {
            editor.commit()
            findCurrent = nil
            editor.pendingReveal = nil
        }
        tabList = updated
        saveTabs()
    }

    func activate(_ id: Note.ID) {
        changeTabs { $0.activate(id) }
    }

    func activateTab(at index: Int) {
        changeTabs { $0.activate(at: index) }
    }

    func keepTab(_ id: Note.ID) {
        guard tabList.preview == id else { return }
        changeTabs { $0.keep(id) }
    }

    func isTabPinned(_ id: Note.ID) -> Bool {
        tabList.isPinned(id)
    }

    func setTabPinned(_ id: Note.ID, _ pinned: Bool) {
        changeTabs { pinned ? $0.pin(id) : $0.unpin(id) }
    }

    func closeTab(_ id: Note.ID) {
        changeTabs { $0.close(id) }
    }

    func closeOtherTabs(_ id: Note.ID) {
        changeTabs { $0.closeOthers(id) }
    }

    func closeTabs(rightOf id: Note.ID) {
        changeTabs { $0.closeRight(of: id) }
    }

    func closeAllTabs() {
        changeTabs { $0.closeAll() }
    }

    func reopenClosedTab() {
        let existing = Set(store.notes.map(\.id))
        changeTabs { $0.reopen(existing: existing) }
    }

    /*
     ⌘W closes the active tab, or the window when no tab is open; like VS Code, a pinned tab is closed only from its menu.
     A sheet or panel in front is left alone.
     */
    func closeCurrentTab() {
        guard let window = NSApp.keyWindow, window.sheetParent == nil, !(window is NSPanel), window.attachedSheet == nil else { return }
        if let selection {
            if !tabList.isPinned(selection) { closeTab(selection) }
        } else {
            window.performClose(nil)
        }
    }

    func middleClickTab() -> Bool {
        guard let id = tabUnderPointer, tabList.ids.contains(id) else { return false }
        if !tabList.isPinned(id) {
            closeTab(id)
            tabUnderPointer = nil
        }
        return true
    }

    func cycleTabs(by offset: Int) {
        changeTabs { $0.cycle(by: offset) }
    }

    /// Notes can vanish under open tabs (deleted, or a file closed), so their tabs go too.
    func pruneTabs() {
        let existing = Set(store.notes.map(\.id))
        changeTabs { $0.prune(keeping: existing) }
    }

    func noteEdited(_ id: Note.ID) {
        keepTab(id)
    }

    func save() {
        editor.commit()
        if let selection { keepTab(selection) }
        store.saveNow()
    }

    func saveTabs() {
        defaults.set(tabList.ids.map(\.uuidString), forKey: Self.tabsKey)
        defaults.set(tabList.pinned.map(\.uuidString), forKey: Self.pinnedTabsKey)
        defaults.set(tabList.active?.uuidString, forKey: Self.activeTabKey)
    }

    func restoreTabs() {
        let saved = (defaults.stringArray(forKey: Self.tabsKey) ?? []).compactMap(UUID.init).filter { store.note($0) != nil }
        let pinned = Set((defaults.stringArray(forKey: Self.pinnedTabsKey) ?? []).compactMap(UUID.init))
        let active = defaults.string(forKey: Self.activeTabKey).flatMap(UUID.init)
        tabList = TabList(ids: saved, active: active, pinned: pinned)
    }
}
