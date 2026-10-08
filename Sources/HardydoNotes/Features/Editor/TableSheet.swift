import AppKit
import HardydoNotesCore
import SwiftUI

struct TableSheet: View {
    let insert: (_ rows: Int, _ columns: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tableRows", store: AppPaths.defaults) private var rows = 2
    @AppStorage("tableColumns", store: AppPaths.defaults) private var columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Table").font(.headline)
            Form {
                Stepper(value: $columns, in: 1...12) {
                    LabeledContent("Columns") { TextField("", value: $columns, format: .number).frame(width: 44).multilineTextAlignment(.trailing) }
                }
                Stepper(value: $rows, in: 1...100) {
                    LabeledContent("Rows") { TextField("", value: $rows, format: .number).frame(width: 44).multilineTextAlignment(.trailing) }
                }
                Text("Not counting the header row, which is always added.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") {
                    // A number still being typed is written back only when its field gives up focus.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    DispatchQueue.main.async {
                        insert(rows, columns)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onChange(of: rows) { rows = min(max(rows, 1), 100) }
        .onChange(of: columns) { columns = min(max(columns, 1), 12) }
    }
}
