import Foundation

/// `board-style.json`: the rendering constants of the SpriteKit board, shared by every theme.
/// Ratios are fractions of one square's side.
public struct BoardStyle: Codable, Hashable, Sendable {
    public let animation: BoardAnimationTiming
    public let zPositions: BoardZPositions
    public let markers: BoardMarkerRatios
    public let focusRing: FocusRingStyle
    public let badge: BoardBadgeStyle
    /// Color of the suggested-move arrow.
    public let hintArrowColor: HexColor
    /// PostScript name of the coordinate label font.
    public let coordinateFontName: String
}

public struct BoardAnimationTiming: Codable, Hashable, Sendable {
    /// A piece sliding from one square to another.
    public let moveSeconds: Double
    /// A captured piece fading out.
    public let captureFadeSeconds: Double
    /// The focus ring moving to another square.
    public let focusSeconds: Double
}

/// Drawing order, back to front; each layer must be above the one listed before it.
public struct BoardZPositions: Codable, Hashable, Sendable {
    public let squares: Double
    public let check: Double
    public let coordinates: Double
    public let legalMarkers: Double
    public let pieces: Double
    /// The correct or incorrect move badge on a square's corner.
    public let badge: Double
    public let hintArrow: Double
    public let focusRing: Double
    /// A piece while it slides or is dragged.
    public let movingPiece: Double

    /// The layers in the order they must stack.
    public var ordered: [Double] {
        [squares, check, coordinates, legalMarkers, pieces, badge, hintArrow, focusRing, movingPiece]
    }
}

public struct BoardMarkerRatios: Codable, Hashable, Sendable {
    /// Side of a piece image.
    public let piece: Double
    /// Diameter of the legal-move dot on an empty square.
    public let legalDot: Double
    /// Outer diameter of the legal-move ring around a capturable piece.
    public let captureRing: Double
    /// Line width of the capture ring.
    public let captureRingWidth: Double
    /// Diameter of the check highlight under the king.
    public let check: Double
    /// Height of the coordinate labels.
    public let coordinateFont: Double
    /// Distance of the coordinate labels from the square edge.
    public let coordinateInset: Double
    public let arrowShaftWidth: Double
    public let arrowHeadWidth: Double
    public let arrowHeadLength: Double
    /// Gap between the source square's center and the start of the arrow.
    public let arrowStartInset: Double

    /// Every ratio, for range checks.
    public var all: [Double] {
        [piece, legalDot, captureRing, captureRingWidth, check, coordinateFont, coordinateInset,
         arrowShaftWidth, arrowHeadWidth, arrowHeadLength, arrowStartInset]
    }
}

/// The round correct or incorrect marker on the top-right corner of a square. Ratios are
/// fractions of one square's side, except `glyphRatio` and `glyphLineRatio`, which are
/// fractions of the badge's diameter.
public struct BoardBadgeStyle: Codable, Hashable, Sendable {
    public let correctColor: HexColor
    public let incorrectColor: HexColor
    /// Color of the check mark or cross.
    public let glyphColor: HexColor
    public let diameterRatio: Double
    /// Distance of the badge's center from the square's top and right edges.
    public let cornerInsetRatio: Double
    /// Size of the check mark or cross.
    public let glyphRatio: Double
    /// Line width of the check mark or cross.
    public let glyphLineRatio: Double

    /// Every ratio, for range checks.
    public var ratios: [Double] { [diameterRatio, cornerInsetRatio, glyphRatio, glyphLineRatio] }
}

public struct FocusRingStyle: Codable, Hashable, Sendable {
    /// Line width as a fraction of the square side.
    public let widthRatio: Double
    /// Smallest line width in points, for small boards.
    public let minimumWidth: Double
    public let color: HexColor
}
