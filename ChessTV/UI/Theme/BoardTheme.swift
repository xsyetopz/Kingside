import SwiftUI
import ChessCore

// Board and piece appearance.
// - `BoardTheme` (.green default, .brown, .blue, .purple): persisted by `rawValue` in AppSettings.
//   Unknown stored values (older theme names) decode to `.green`.
//   Colors: `lightSquare`, `darkSquare`, `lastMove(light:)`, `selected(light:)`,
//   `squareColor(isLight:)`, `coordinateColor(isLight:)`; `Square.isLight` tells which applies.
// - `PieceSet` (.cburnett): `imageName(for:)` / `image(for:)` return the asset for a `Piece`.

enum BoardTheme: String, Codable, CaseIterable, Identifiable {
    case green, brown, blue, purple

    var id: String { rawValue }
    var title: String {
        switch self {
        case .green: "Green"
        case .brown: "Brown"
        case .blue: "Icy Blue"
        case .purple: "Purple"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BoardTheme(rawValue: raw) ?? .green
    }

    var lightSquare: Color {
        switch self {
        case .green: Color(hex: 0xEEEED2)
        case .brown: Color(hex: 0xF0D9B5)
        case .blue: Color(hex: 0xDEE3E6)
        case .purple: Color(hex: 0xE8E0F0)
        }
    }

    var darkSquare: Color {
        switch self {
        case .green: Color(hex: 0x769656)
        case .brown: Color(hex: 0xB58863)
        case .blue: Color(hex: 0x8CA2AD)
        case .purple: Color(hex: 0x9F90B0)
        }
    }

    /// Last-move tint: the square color mixed about 50% with yellow.
    func lastMove(light: Bool) -> Color {
        switch self {
        case .green: Color(hex: light ? 0xF6F669 : 0xBACA2B)
        case .brown: Color(hex: light ? 0xF7EC74 : 0xDAC34B)
        case .blue: Color(hex: light ? 0xEEF18C : 0xC5D070)
        case .purple: Color(hex: light ? 0xF4F092 : 0xCFC872)
        }
    }

    /// Selected-piece tint: the square color mixed about 70% with yellow.
    func selected(light: Bool) -> Color {
        switch self {
        case .green: Color(hex: light ? 0xFAFA63 : 0xD6E03E)
        case .brown: Color(hex: light ? 0xFAF45A : 0xE3DB42)
        case .blue: Color(hex: light ? 0xF5F669 : 0xDCE358)
        case .purple: Color(hex: light ? 0xF8F66C : 0xE2DE59)
        }
    }

    func squareColor(isLight: Bool) -> Color { isLight ? lightSquare : darkSquare }

    /// Coordinate labels use the opposite square color so they read on either square.
    func coordinateColor(isLight: Bool) -> Color { isLight ? darkSquare : lightSquare }
}

extension Square {
    /// a1 is dark, h1 is light.
    var isLight: Bool { !(file + rank).isMultiple(of: 2) }
}

enum PieceSet: String, Codable, CaseIterable, Identifiable {
    case cburnett

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Asset name such as `cburnett-wK`.
    func imageName(for piece: Piece) -> String {
        let color = piece.color == .white ? "w" : "b"
        let letter = piece.type == .pawn ? "P" : piece.type.sanLetter
        return "\(rawValue)-\(color)\(letter)"
    }

    func image(for piece: Piece) -> Image { Image(imageName(for: piece)) }
}
