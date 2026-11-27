import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var r: Double = 0, g: Double = 0, b: Double = 0
        if s.count == 6, let v = UInt64(s, radix: 16) {
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8) & 0xFF) / 255.0
            b = Double(v & 0xFF) / 255.0
        }
        self.init(red: r, green: g, blue: b)
    }
}

enum Theme {
    static let pageBackground = Color(hex: "#0B1220")
    static let cardBackground = Color(hex: "#16202E")
    static let cardBorder = Color(hex: "#24324A")
    static let primaryText = Color(hex: "#E6EDF7")
    static let secondaryText = Color(hex: "#8CA0BC")
    static let accent = Color(hex: "#4CC9F0")
    static let userBubble = Color(hex: "#1D4ED8")
    static let danger = Color(hex: "#F87171")
    static let warning = Color(hex: "#F59E0B")
    static let divider = Color(hex: "#24324A")
    static let inputBackground = Color(hex: "#0F1A2B")
    static let success = Color(hex: "#4ADE80")
    static let reasoningText = Color(hex: "#7C8DB0")

    static func agentColor(_ name: String) -> Color {
        Color(hex: agentColorHex(name))
    }
}
