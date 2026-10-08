import Combine
import SwiftUI

/// State owned by one view. This SDK's `@State` is a macro whose plugin ships only with Xcode, so views keep it here instead.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
