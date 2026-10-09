import HardydoNotesCore

extension AppModel {
    func tabPlan(lifting id: Note.ID) -> ReorderPlan? {
        guard let slots = tabList.slotRange(moving: id) else { return nil }
        let remaining = tabList.ids.filter { $0 != id }
        return ReorderPlan(rows: tabList.ids, block: [id], isSlot: { index, upper in !upper && slots.contains(index) }) { [weak self] drop in
            guard let index = drop.index else { return }
            var order = remaining
            order.insert(id, at: index)
            self?.changeTabs { $0.reorder(order) }
        }
    }
}
