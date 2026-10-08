import AppKit
import HardydoNotesCore
import UniformTypeIdentifiers

extension AppModel {
    func sidebarPlan(lifting id: UUID) -> ReorderPlan? {
        reorderPlan(lifting: id, in: store.appNotes, groups: groups, regroups: true)
    }

    func filePlan(lifting id: UUID) -> ReorderPlan? {
        reorderPlan(lifting: id, in: store.localFileNotes, groups: NoteGroups(), regroups: false)
    }

    private func reorderPlan(lifting id: UUID, in notes: [Note], groups: NoteGroups, regroups: Bool) -> ReorderPlan? {
        guard let plan = groups.reorderPlan(moving: id, in: notes) else { return nil }
        func result(_ drop: ReorderDrop) -> SidebarReorderPlan.Result? {
            guard case .slot(let index, let upper) = drop else { return nil }
            return upper ? plan.upperSlots[index] : plan.slots[index]
        }
        return ReorderPlan(
            rows: plan.rows, block: plan.block, slots: Set(plan.slots.keys), upperSlots: Set(plan.upperSlots.keys),
            startsUpper: plan.startsUpper, into: plan.into, lane: { result($0)?.groups.group(of: id)?.id }
        ) { [weak self] drop in
            guard let self else { return }
            if case .into(let group) = drop {
                add(id, toGroup: group)
            } else if let result = result(drop) {
                store.reorder(result.order)
                if regroups { changeGroups { $0 = result.groups } }
            }
        }
    }

    /// Pinned tabs move among pinned tabs, the others after them.
    func tabPlan(lifting id: Note.ID) -> ReorderPlan? {
        let ids = tabList.ids
        guard ids.contains(id) else { return nil }
        let remaining = ids.filter { $0 != id }
        let pinned = tabList.isPinned(id)
        let pinnedCount = tabList.pinnedCount - (pinned ? 1 : 0)
        let slots = pinned ? Set(0...pinnedCount) : Set(pinnedCount...remaining.count)
        return ReorderPlan(rows: ids, block: [id], slots: slots) { [weak self] drop in
            guard let index = drop.index else { return }
            var order = remaining
            order.insert(id, at: index)
            self?.changeTabs { $0.reorder(order) }
        }
    }

    func openDropped(_ providers: [NSItemProvider], at position: Int) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { open(urls, at: position) }
        }
    }
}
