import SwiftUI

/// Kino design tokens — original visual identity.
public enum KinoTheme {
    // Palette
    public static let ink0 = Color(hex: 0x0A0B0E)      // app background
    public static let ink1 = Color(hex: 0x121317)      // elevated surface
    public static let ink2 = Color(hex: 0x1A1C22)      // card surface
    public static let ink3 = Color(hex: 0x23262E)      // control surface
    public static let ink4 = Color(hex: 0x2E323C)      // control surface pressed
    public static let hairline = Color(hex: 0x2A2D35)  // separators
    public static let textPrimary = Color(hex: 0xF2F3F7)
    public static let textSecondary = Color(hex: 0x9BA1AD)
    public static let textTertiary = Color(hex: 0x5F6672)

    // Accent — "Kinora" violet → cyan family
    public static let accentOld = Color(hex: 0x7C5CFF)
    public static let accent = Color(hex: 0x8A6CFF)
    public static let accentSoft = Color(hex: 0xB3A2FF)
    public static let accentCyan = Color(hex: 0x4DD8FF)
    public static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x8A6CFF), Color(hex: 0x4DD8FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Semantic
    public static let danger = Color(hex: 0xFF5B5B)
    public static let success = Color(hex: 0x53D582)
    public static let warning = Color(hex: 0xFFCC55)

    public static let backgroundColor = ink0

    // Radii
    public static let radiusSmall: CGFloat = 8
    public static let radiusMedium: CGFloat = 12
    public static let radiusLarge: CGFloat = 18
    public static let radiusPill: CGFloat = 999

    // Spacing scale
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 12
    public static let space4: CGFloat = 16
    public static let space5: CGFloat = 20
    public static let space6: CGFloat = 24
    public static let space8: CGFloat = 32
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// Central haptics policy.
enum KinoHaptics {
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func snap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
        #endif
    }
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
