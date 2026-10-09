import AppKit
import HardydoNotesCore
import SwiftUI

struct TableSheet: View {
    let insert: (_ rows: Int, _ columns: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var rows: Int
    @AppStorage private var columns: Int

    init(preferences: Preferences, insert: @escaping (_ rows: Int, _ columns: Int) -> Void) {
        self.insert = insert
        _rows = AppStorage(wrappedValue: 2, Preferences.Key.tableRows, store: preferences.defaults)
        _columns = AppStorage(wrappedValue: 2, Preferences.Key.tableColumns, store: preferences.defaults)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Table").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Columns").gridColumnAlignment(.trailing)
                    NumberField(value: $columns, range: 1...12)
                }
                GridRow {
                    Text("Rows")
                    NumberField(value: $rows, range: 1...100)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("A header row is always added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
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

private struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $value, format: .number)
                .frame(width: 44)
                .multilineTextAlignment(.trailing)
            Stepper("", value: $value, in: range).labelsHidden()
        }
    }
}
