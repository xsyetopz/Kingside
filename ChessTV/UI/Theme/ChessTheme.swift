import SwiftUI

// Design system: dark, warm-grey palette with a raised green accent.
// - `ChessTheme` holds the colors (`background`, `panel`, `raised`, `focusSurface`, text tones,
//   `primary`/`primaryEdge`, `secondary`/`secondaryEdge`, `win`/`loss`/`draw`, clock colors).
// - `ChessFont` holds 10-foot typography (body >= 28pt, rounded heavy headings).
// - `.chessScreen()` paints the app background; `.chessPanel()` paints a sidebar/panel box.
// - Button styles live in ChessButtonStyles.swift; board colors in BoardTheme.swift.
// Platform-neutral (no tvOS-only API), so it can be rendered offline on macOS.

enum ChessTheme {
    // Surfaces
    static let background = Color(hex: 0x312E2B)
    static let panel = Color(hex: 0x262522)
    static let raised = Color(hex: 0x3C3936)
    static let focusSurface = Color(hex: 0x4B4845)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xC3C2C1)
    static let textMuted = Color(hex: 0x8B8987)

    // Buttons
    static let primary = Color(hex: 0x81B64C)
    static let primaryFocused = Color(hex: 0x95C95E)
    static let primaryEdge = Color(hex: 0x45753C)
    static let secondary = Color(hex: 0x4B4847)
    static let secondaryFocused = Color(hex: 0x5D5A58)
    static let secondaryEdge = Color(hex: 0x3A3735)

    // Results
    static let win = Color(hex: 0x81B64C)
    static let loss = Color(hex: 0xE02828)
    static let lossBright = Color(hex: 0xFA412D)
    static let draw = Color(hex: 0x8B8987)

    // Clocks
    static let clockActive = Color.white
    static let clockActiveText = Color(hex: 0x262522)
    static let clockInactive = Color(hex: 0x21201D)
    static let clockInactiveText = Color(hex: 0x8B8987)
    static let clockLow = Color(hex: 0xE02828)

    /// Standard corner radius for panels and buttons.
    static let cornerRadius: CGFloat = 12

    // Legacy aliases used by screens that have not been rewritten yet. New code should use the
    // names above.
    static let surface = panel
    static let surfaceRaised = raised
    static let accent = primary
    static let legal = win
    static let danger = lossBright
}

/// Typography sized for a TV viewed from about 10 feet.
enum ChessFont {
    static let display = Font.system(size: 76, weight: .heavy, design: .rounded)
    static let title = Font.system(size: 54, weight: .heavy, design: .rounded)
    static let heading = Font.system(size: 38, weight: .bold, design: .rounded)
    static let subheading = Font.system(size: 32, weight: .bold)
    static let body = Font.system(size: 28, weight: .semibold)
    static let bodyRegular = Font.system(size: 28, weight: .regular)
    static let caption = Font.system(size: 24, weight: .semibold)
    static let button = Font.system(size: 32, weight: .bold, design: .rounded)
    static let clock = Font.system(size: 44, weight: .bold, design: .rounded).monospacedDigit()

    /// A custom size in the same family: rounded for headings, default design for text.
    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    /// Creates an sRGB color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(ChessTheme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ChessTheme.background.ignoresSafeArea())
    }
}

private struct PanelBackground: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(ChessTheme.panel, in: RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous))
    }
}

extension View {
    /// Full-screen app background (#312E2B) with white default text.
    func chessScreen() -> some View { modifier(ScreenBackground()) }

    /// Non-focusable sidebar/panel box (#262522) with rounded corners.
    func chessPanel(padding: CGFloat = 28) -> some View { modifier(PanelBackground(padding: padding)) }
}
