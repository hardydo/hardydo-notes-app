import Foundation
import HardydoNotesCore
import Testing

@Suite struct TabListTests {
    @Test func singleClickOpensReplaceablePreviewTab() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var tabs = TabList()
        tabs.open(a, keep: false)
        #expect(tabs.ids == [a], "first click opens a preview tab")
        #expect(tabs.transient == a, "single click tab is a preview")
        tabs.open(b, keep: false)
        #expect(tabs.ids == [b] && tabs.active == b, "next single click replaces the preview tab")
        tabs.keep(b)
        tabs.open(c, keep: false)
        #expect(tabs.ids == [b, c] && tabs.transient == c, "a kept tab stays when another note is clicked")
        tabs.open(b, keep: false)
        #expect(tabs.ids == [b, c] && tabs.active == b && tabs.transient == c, "clicking an open note reuses its tab")
        tabs.open(d, keep: true)
        #expect(tabs.ids == [b, d, c], "a kept tab opens right of the active one")
        #expect(tabs.transient == c, "opening a kept tab leaves the preview alone")
        tabs.open(c, keep: true)
        #expect(tabs.transient == nil && tabs.active == c, "keeping the preview tab makes it permanent")
    }

    @Test func closingActiveTabMovesToItsNeighbour() {
        let b = UUID(), c = UUID(), d = UUID()
        var tabs = TabList(ids: [b, d, c], active: c)
        tabs.activate(d)
        tabs.close(d)
        #expect(tabs.active == c, "closing the active tab moves to its right")
        tabs.close(c)
        #expect(tabs.active == b, "closing the last tab moves to its left")
        tabs.close(b)
        #expect(tabs.ids.isEmpty && tabs.active == nil, "closing every tab leaves nothing active")
    }

    @Test func closingTabsToTheRightAndOthersKeepsTheTarget() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var tabs = TabList(ids: [a, b, c, d], active: b)
        tabs.closeRight(of: a)
        #expect(tabs.ids == [a] && tabs.active == a, "closing tabs to the right moves off a closed active tab")
        tabs = TabList(ids: [a, b, c], active: c)
        tabs.closeOthers(b)
        #expect(tabs.ids == [b] && tabs.active == b, "close others keeps only that tab")
    }

    @Test func cyclingWrapsAroundAndReorderFollowsTheDrop() {
        let a = UUID(), b = UUID(), c = UUID()
        var tabs = TabList(ids: [a, b, c], active: a)
        tabs.cycle(by: -1)
        #expect(tabs.active == c, "previous tab wraps around")
        tabs.cycle(by: 1)
        #expect(tabs.active == a, "next tab wraps around")
        tabs.reorder([b, c, a])
        #expect(tabs.ids == [b, c, a], "a dragged tab lands where it was dropped")
    }

    @Test func pruningClosesTabsOfVanishedNotes() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var tabs = TabList(ids: [a, b, c], active: b)
        tabs.prune(keeping: [a, c])
        #expect(tabs.ids == [a, c] && tabs.active == c, "tabs of vanished notes close and the active tab moves on")
        #expect(TabList(ids: [a, b], active: d).active == a, "restored tabs fall back to the first tab")
    }

    @Test func pinnedTabMovesToTheFrontAndNewTabsOpenAfterPins() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var tabs = TabList(ids: [a, b, c], active: a)
        tabs.pin(c)
        #expect(tabs.ids == [c, a, b], "a pinned tab moves to the front")
        #expect(tabs.isPinned(c) && !tabs.isPinned(a), "only the pinned tab reports pinned")
        tabs.open(d, keep: true)
        tabs.activate(c)
        tabs.open(UUID(), keep: true)
        #expect(tabs.ids.firstIndex(of: c) == 0 && tabs.pinnedCount == 1, "new tabs never open among pinned ones")
    }

    @Test func restoredPinsComeFirstAndCloseAllKeepsThem() {
        let a = UUID(), b = UUID(), c = UUID()
        var tabs = TabList(ids: [a, b, c], active: b, pinned: [b])
        #expect(tabs.ids == [b, a, c], "restored pins come first")
        tabs.closeAll()
        #expect(tabs.ids == [b], "close all keeps pinned tabs")
    }

    @Test func closeOthersKeepsPinnedTabs() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var tabs = TabList(ids: [a, b, c, d], active: c, pinned: [a])
        tabs.closeOthers(c)
        #expect(tabs.ids == [a, c], "close others keeps pinned tabs")
    }

    @Test func closeRightKeepsPinnedTabsAndCloseCommandsFollowThem() {
        let a = UUID(), b = UUID(), c = UUID()
        var tabs = TabList(ids: [a, b, c], active: c, pinned: [a, b])
        tabs.closeRight(of: a)
        #expect(tabs.ids == [a, b], "close to the right keeps pinned tabs")
        #expect(!tabs.canCloseAll && !tabs.canCloseOthers(a) && !tabs.canCloseRight(of: a), "close commands are off when only pinned tabs are left")
        tabs.open(c, keep: true)
        #expect(tabs.canCloseOthers(a) && tabs.canCloseRight(of: a) && !tabs.canCloseRight(of: c), "close commands turn on while an unpinned tab can close")
        tabs.close(c)
        tabs.reorder([b, a])
        #expect(tabs.ids == [b, a], "pinned tabs reorder among themselves")
        tabs.unpin(b)
        #expect(tabs.ids == [a, b] && !tabs.isPinned(b), "an unpinned tab goes right after the pinned ones")
    }

    @Test func dragNeverCrossesThePinnedBoundary() {
        let a = UUID(), b = UUID(), c = UUID()
        var tabs = TabList(ids: [a, b, c], active: a, pinned: [a])
        tabs.reorder([b, a, c])
        #expect(tabs.ids == [a, b, c], "a drag never moves a tab across the pinned boundary")
        tabs.reorder([a, b])
        #expect(tabs.ids == [a, b, c], "an order missing a tab is ignored")
        tabs.reorder([a, c, b])
        #expect(tabs.ids == [a, c, b], "unpinned tabs reorder after the pinned ones")
    }

    @Test func reopeningBringsBackTheLastClosedTab() {
        let a = UUID(), b = UUID(), c = UUID()
        var tabs = TabList(ids: [a, b, c], active: b)
        tabs.close(b)
        tabs.close(c)
        #expect(tabs.reopen(existing: [a, b, c]) == c, "reopen brings back the last closed tab")
        #expect(tabs.reopen(existing: [a, c]) == nil, "a deleted note is not reopened")
        tabs = TabList(ids: [a, b], active: a, pinned: [a])
        tabs.close(a)
        tabs.reopen(existing: [a, b])
        #expect(tabs.isPinned(a) && tabs.ids == [a, b], "a reopened pinned tab is pinned again")
        tabs.activate(at: 1)
        #expect(tabs.active == b, "activate by position")
    }
}
