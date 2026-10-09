import SwiftUI

/// Shown when no note is open: the app's mark, then the shortcuts that get somewhere, each one also clickable.
struct EmptyWorkspace: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            AppMark()
                .frame(width: 60, height: 72)
            VStack(spacing: 0) {
                shortcut("New Note", ["⌘", "N"]) { model.newNote() }
                shortcut("Go to Note", ["⌘", "P"]) { model.quickOpen.show() }
                shortcut("Search All Notes", ["⇧", "⌘", "F"]) { model.openGlobalSearch() }
                shortcut("Toggle Sidebar", ["⌘", "B"]) { model.toggleSidebar() }
                shortcut("Open File", ["⌘", "O"]) { model.showOpenPanel() }
            }
            .frame(width: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -20)
    }

    private func shortcut(_ title: String, _ keys: [String], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13.5))
                Spacer(minLength: 24)
                HStack(spacing: 3) {
                    ForEach(keys, id: \.self) { Keycap(key: $0) }
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.icon)
    }
}

private struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .frame(minWidth: 20, minHeight: 20)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .offset(y: 1.5)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            }
    }
}

/// The app's "h." mark in its dark-theme colours (Resources/brand/h-mark-dark.svg).
struct AppMark: View {
    var body: some View {
        ZStack {
            AppMarkPart(isDot: false).fill(Color(red: 0xEF / 255, green: 0xE9 / 255, blue: 0xDF / 255))
            AppMarkPart(isDot: true).fill(Color(red: 0xE8 / 255, green: 0xA3 / 255, blue: 0x4A / 255))
        }
    }
}

private struct AppMarkPart: Shape {
    let isDot: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isDot {
            path.addEllipse(in: CGRect(x: 192, y: 240, width: 60, height: 60))
        } else {
            path.addRect(CGRect(x: 0, y: 0, width: 52, height: 300))
            path.move(to: CGPoint(x: 0, y: 190))
            path.addArc(center: CGPoint(x: 87, y: 190), radius: 87, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: 174, y: 300))
            path.addLine(to: CGPoint(x: 122, y: 300))
            path.addLine(to: CGPoint(x: 122, y: 190))
            path.addArc(center: CGPoint(x: 87, y: 190), radius: 35, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            path.closeSubpath()
        }
        let scale = min(rect.width / 252, rect.height / 300)
        let origin = CGPoint(x: rect.midX - 126 * scale, y: rect.midY - 150 * scale)
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x, ty: origin.y))
    }
}
