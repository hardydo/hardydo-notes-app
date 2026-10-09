import AppKit
import HardydoNotesCore
import Observation

struct TabChange {
    let old: Note.ID?
    let new: Note.ID?
    let ids: [Note.ID]
}

@MainActor
@Observable
final class TabsModel {
    private(set) var list = TabList()
    @ObservationIgnored let reorder = ReorderSession(axis: .horizontal, space: "tabs")
    @ObservationIgnored var underPointer: Note.ID?
    /*
     Set by the owner before `restore()`. `leaving` runs while the old tab is still active, just before another
     becomes so; `changed` runs after every change.
     */
    @ObservationIgnored var leaving: () -> Void = {}
    @ObservationIgnored var changed: (TabChange) -> Void = { _ in }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private let store: NoteStore
    private let preferences: Preferences

    init(store: NoteStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
    }

    var selection: Note.ID? { list.active }
    var transient: Note.ID? { list.transient }

    var notes: [Note] {
        list.ids.compactMap(store.note)
    }

    func change(_ change: (inout TabList) -> Void) {
        let before = list.active
        var updated = list
        change(&updated)
        guard updated != list else { return }
        if updated.active != before { leaving() }
        list = updated
        changed(TabChange(old: before, new: updated.active, ids: updated.ids))
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Shows a note in a tab: an open tab is reused, otherwise it opens in the transient tab unless `keep` is set.
    func open(_ id: Note.ID, keep: Bool = false) {
        change { $0.open(id, keep: keep) }
    }

    func activate(_ id: Note.ID) {
        change { $0.activate(id) }
    }

    func activate(at index: Int) {
        change { $0.activate(at: index) }
    }

    func keep(_ id: Note.ID) {
        guard list.transient == id else { return }
        change { $0.keep(id) }
    }

    func isPinned(_ id: Note.ID) -> Bool {
        list.isPinned(id)
    }

    func setPinned(_ id: Note.ID, _ pinned: Bool) {
        change { pinned ? $0.pin(id) : $0.unpin(id) }
    }

    func close(_ id: Note.ID) {
        change { $0.close(id) }
    }

    func closeOthers(_ id: Note.ID) {
        change { $0.closeOthers(id) }
    }

    func closeRight(of id: Note.ID) {
        change { $0.closeRight(of: id) }
    }

    func closeAll() {
        change { $0.closeAll() }
    }

    func reopen() {
        let existing = Set(store.notes.map(\.id))
        change { $0.reopen(existing: existing) }
    }

    /*
     ⌘W closes the active tab, or the window when no tab is open; like VS Code, a pinned tab is closed only from its menu.
     A sheet or panel in front is left alone.
     */
    func closeCurrent() {
        guard let window = NSApp.keyWindow, window.sheetParent == nil, !(window is NSPanel), window.attachedSheet == nil else { return }
        if let selection {
            if !list.isPinned(selection) { close(selection) }
        } else {
            window.performClose(nil)
        }
    }

    func middleClick() -> Bool {
        guard let id = underPointer, list.ids.contains(id) else { return false }
        if !list.isPinned(id) {
            close(id)
            underPointer = nil
        }
        return true
    }

    func cycle(by offset: Int) {
        change { $0.cycle(by: offset) }
    }

    func prune() {
        let existing = Set(store.notes.map(\.id))
        change { $0.prune(keeping: existing) }
    }

    /// Tabs refer to notes by id, so they are only saved against a notes list that loaded whole.
    func save() {
        saveTask?.cancel()
        guard store.loadedCleanly else { return }
        preferences.openTabs = list.ids
        preferences.pinnedTabs = Array(list.pinned)
        preferences.activeTab = list.active
    }

    func restore() {
        let saved = preferences.openTabs.filter { store.note($0) != nil }
        let before = list.active
        list = TabList(ids: saved, active: preferences.activeTab, pinned: Set(preferences.pinnedTabs))
        changed(TabChange(old: before, new: list.active, ids: list.ids))
    }

    func plan(lifting id: Note.ID) -> ReorderPlan? {
        guard let slots = list.slotRange(moving: id) else { return nil }
        let remaining = list.ids.filter { $0 != id }
        return ReorderPlan(rows: list.ids, block: [id], isSlot: { index, upper in !upper && slots.contains(index) }) { [weak self] drop in
            guard let index = drop.index else { return }
            var order = remaining
            order.insert(id, at: index)
            self?.change { $0.reorder(order) }
        }
    }
}
