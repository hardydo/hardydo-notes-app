import Combine
import SwiftUI

/// State owned by one view. This SDK's `@State` is a macro whose plugin ships only with Xcode, so views keep it here instead.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Like `ViewState`, but only the views that read `value` redraw when it changes, not the view that owns it.
@Observable
final class ObservedState<Value>: ObservableObject {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
