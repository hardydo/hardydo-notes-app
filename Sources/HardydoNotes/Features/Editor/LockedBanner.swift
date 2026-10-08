import SwiftUI

struct LockedBanner: View {
    let unlock: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text("This note is locked and read-only.")
            Spacer()
            Button("Unlock", action: unlock).controlSize(.small)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
