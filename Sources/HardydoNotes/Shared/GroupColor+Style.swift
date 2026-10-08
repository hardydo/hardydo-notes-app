import HardydoNotesCore
import SwiftUI

extension GroupColor {
    var color: Color {
        switch self {
        case .blue: Color(red: 0.40, green: 0.62, blue: 0.97)
        case .pink: Color(red: 0.94, green: 0.42, blue: 0.69)
        case .orchid: Color(red: 0.82, green: 0.55, blue: 0.87)
        case .lavender: Color(red: 0.71, green: 0.61, blue: 0.98)
        case .steel: Color(red: 0.31, green: 0.55, blue: 0.77)
        case .teal: Color(red: 0.29, green: 0.71, blue: 0.69)
        case .orange: Color(red: 0.90, green: 0.57, blue: 0.42)
        case .gold: Color(red: 0.80, green: 0.67, blue: 0.33)
        case .grey: Color(red: 0.56, green: 0.56, blue: 0.56)
        }
    }

    var label: String {
        switch self {
        case .blue: "Blue"
        case .pink: "Pink"
        case .orchid: "Orchid"
        case .lavender: "Lavender"
        case .steel: "Steel Blue"
        case .teal: "Teal"
        case .orange: "Orange"
        case .gold: "Gold"
        case .grey: "Grey"
        }
    }
}
