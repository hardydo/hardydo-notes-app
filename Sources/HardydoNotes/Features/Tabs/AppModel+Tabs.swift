import AppKit
import HardydoNotesCore

extension AppModel {

    var selection: Note.ID? { tabList.active }
    var transientTab: Note.ID? { tabList.transient }

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
            find.current = nil
            editor.pendingReveal = nil
        }
        tabList = updated
        editor.keepSessions(for: updated.ids)
        keepLanguages(for: Set(updated.ids))
        tabSaveTask?.cancel()
        tabSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveTabs()
        }
    }

    func activate(_ id: Note.ID) {
        changeTabs { $0.activate(id) }
    }

    func activateTab(at index: Int) {
        changeTabs { $0.activate(at: index) }
    }

    func keepTab(_ id: Note.ID) {
        guard tabList.transient == id else { return }
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
        tabSaveTask?.cancel()
        guard persistsSidebarState else { return }
        preferences.openTabs = tabList.ids
        preferences.pinnedTabs = Array(tabList.pinned)
        preferences.activeTab = tabList.active
    }

    func restoreTabs() {
        let saved = preferences.openTabs.filter { store.note($0) != nil }
        let pinned = Set(preferences.pinnedTabs)
        let active = preferences.activeTab
        tabList = TabList(ids: saved, active: active, pinned: pinned)
    }
}
