import Foundation
import HardydoNotesCore

extension GroupsModel {
    func sidebarPlan(lifting id: UUID) -> ReorderPlan? {
        reorderPlan(lifting: id, in: store.appNotes, groups: list, regroups: true)
    }

    func filePlan(lifting id: UUID) -> ReorderPlan? {
        reorderPlan(lifting: id, in: store.localFileNotes, groups: NoteGroups(), regroups: false)
    }

    private func reorderPlan(lifting id: UUID, in notes: [Note], groups: NoteGroups, regroups: Bool) -> ReorderPlan? {
        guard let plan = groups.reorderPlan(moving: id, in: notes) else { return nil }
        func result(_ drop: ReorderDrop) -> SidebarReorderPlan.Result? {
            guard case .slot(let index, let upper) = drop else { return nil }
            return plan.result(at: index, upper: upper)
        }
        return ReorderPlan(
            rows: plan.rows, block: plan.block, isSlot: { plan.result(at: $0, upper: $1) != nil }, headers: Set(groups.groups.map(\.id)),
            startsUpper: plan.startsUpper, into: plan.into, lane: { result($0)?.groups.group(of: id)?.id }
        ) { [weak self] drop in
            guard let self else { return }
            if case .into(let group) = drop {
                add(id, to: group)
            } else if let result = result(drop) {
                store.reorder(result.order)
                if regroups { change { $0 = result.groups } }
            }
        }
    }
}
