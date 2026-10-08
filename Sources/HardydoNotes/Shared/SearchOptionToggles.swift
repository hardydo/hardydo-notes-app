import HardydoNotesCore
import SwiftUI

/// VS Code's Aa / ab / .* toggles, shared by Find and Search All Notes.
struct SearchOptionToggles: View {
    let options: SearchOptions
    let onChange: (SearchOptions) -> Void

    var body: some View {
        HStack(spacing: 2) {
            toggle("Aa", "Match Case", \.caseSensitive)
            toggle("ab", "Match Whole Word", \.wholeWord, underline: true)
            toggle(".*", "Use Regular Expression", \.regex)
        }
    }

    private func toggle(_ label: String, _ help: String, _ key: WritableKeyPath<SearchOptions, Bool>, underline: Bool = false) -> some View {
        let isOn = options[keyPath: key]
        return Button {
            var updated = options
            updated[keyPath: key].toggle()
            onChange(updated)
        } label: {
            Text(label)
                .underline(underline)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .frame(width: 22, height: 18)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(isOn ? Color.accentColor.opacity(0.18) : .clear))
        }
        .buttonStyle(IconButtonStyle(tint: isOn ? .accentColor : nil))
        .help(help)
    }
}
