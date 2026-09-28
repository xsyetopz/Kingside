import SwiftUI

enum ChessTheme {
    static let background = Color(red: 0.025, green: 0.04, blue: 0.07)
    static let surface = Color(red: 0.075, green: 0.10, blue: 0.15)
    static let surfaceRaised = Color(red: 0.11, green: 0.14, blue: 0.20)
    static let accent = Color(red: 0.30, green: 0.84, blue: 0.77)
    static let accentWarm = Color(red: 0.96, green: 0.67, blue: 0.30)
    static let lightSquare = Color(red: 0.73, green: 0.76, blue: 0.72)
    static let darkSquare = Color(red: 0.21, green: 0.31, blue: 0.34)
    static let selected = Color(red: 0.98, green: 0.72, blue: 0.20)
    static let legal = Color(red: 0.20, green: 0.92, blue: 0.72)
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.35)

    static let backdrop = LinearGradient(
        colors: [background, Color(red: 0.04, green: 0.09, blue: 0.13)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension BoardTheme {
    var lightSquareColor: Color {
        switch self {
        case .tournament: Color(red: 0.93, green: 0.92, blue: 0.84)
        case .midnight: Color(red: 0.69, green: 0.75, blue: 0.75)
        case .ocean: Color(red: 0.67, green: 0.82, blue: 0.85)
        case .walnut: Color(red: 0.82, green: 0.71, blue: 0.57)
        }
    }

    var darkSquareColor: Color {
        switch self {
        case .tournament: Color(red: 0.075, green: 0.43, blue: 0.18)
        case .midnight: Color(red: 0.16, green: 0.26, blue: 0.31)
        case .ocean: Color(red: 0.08, green: 0.34, blue: 0.43)
        case .walnut: Color(red: 0.36, green: 0.20, blue: 0.15)
        }
    }

    var edgeColor: Color {
        switch self {
        case .tournament: Color(red: 0.045, green: 0.31, blue: 0.12)
        case .midnight: Color(red: 0.08, green: 0.17, blue: 0.21)
        case .ocean: Color(red: 0.04, green: 0.25, blue: 0.33)
        case .walnut: Color(red: 0.24, green: 0.12, blue: 0.08)
        }
    }
}

struct TVCardStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(28)
            .background(isFocused ? ChessTheme.surfaceRaised : ChessTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isFocused ? ChessTheme.accent : .white.opacity(0.08), lineWidth: isFocused ? 4 : 1)
            }
            .shadow(color: isFocused ? ChessTheme.accent.opacity(0.30) : .clear, radius: 24)
            .scaleEffect(isFocused ? 1.055 : 1)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ChessTheme.backdrop.ignoresSafeArea())
    }
}

extension View {
    func chessScreen() -> some View { modifier(ScreenBackground()) }
}
