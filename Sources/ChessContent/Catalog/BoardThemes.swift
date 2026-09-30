import Foundation

/// `board-themes.json` entry: the colors of a procedurally drawn board.
public struct BoardTheme: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let nameKey: String
    public let squares: SquareColors
    /// Tint for the from and to squares of the last move.
    public let lastMove: SquareColors
    /// Tint for the square of the selected piece.
    public let selection: SquareColors
    /// Coordinate label color drawn on each kind of square.
    public let coordinates: SquareColors
    /// Legal-move marker, usually translucent.
    public let legalMove: HexColor
    /// Highlight under a king in check, usually translucent.
    public let check: HexColor
}

/// A color for light squares and one for dark squares.
public struct SquareColors: Codable, Hashable, Sendable {
    public let light: HexColor
    public let dark: HexColor

    public func color(isLight: Bool) -> HexColor { isLight ? light : dark }
}
