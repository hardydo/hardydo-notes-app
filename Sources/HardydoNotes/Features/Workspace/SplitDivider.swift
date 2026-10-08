import AppKit
import SwiftUI

struct SplitDivider: View {
    static let space = "split"
    static let thickness: CGFloat = 8
    let width: CGFloat
    let onDrag: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: Self.thickness)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { onDrag(width > 0 ? $0.location.x / width : 0.5) }
                    .onEnded { _ in onEnd() }
            )
    }
}
