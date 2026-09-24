import SwiftUI

extension Color {
    /// stacker.news primary yellow (`$primary` in styles/globals.scss).
    static let snYellow = Color(red: 0.980, green: 0.855, blue: 0.369)
    /// Dark-theme muted grey (`--theme-grey`).
    static let snGrey = Color(red: 0.588, green: 0.588, blue: 0.588)
    /// Dark-theme link blue (`--theme-link`).
    static let snLink = Color(red: 0.180, green: 0.600, blue: 0.820)
}

/// Lets the colors above be used as `.foregroundStyle(.snYellow)`.
extension ShapeStyle where Self == Color {
    static var snYellow: Color { Color.snYellow }
    static var snGrey: Color { Color.snGrey }
    static var snLink: Color { Color.snLink }
}

enum Format {
    /// 9419 -> "9.4k", 1_200_000 -> "1.2m"
    static func sats(_ value: Int) -> String {
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return trimmed(Double(value) / 1_000) + "k"
        default: return trimmed(Double(value) / 1_000_000) + "m"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func age(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }
}
