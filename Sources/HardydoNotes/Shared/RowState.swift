import Foundation

/// A sidebar row's selection, observed by that row alone, so moving the selection redraws two rows instead of the list.
@MainActor
@Observable
final class RowState {
    var isSelected: Bool

    init(isSelected: Bool) {
        self.isSelected = isSelected
    }
}
