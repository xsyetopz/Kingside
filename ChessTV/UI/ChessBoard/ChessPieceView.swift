import SwiftUI
import ChessCore

// A single flat 2D piece image from a `PieceSet`, scaled to fit its frame.
// Usage: `ChessPieceView(piece: Piece(type: .knight, color: .white))` or
// `ChessPieceView(piece: piece, pieceSet: .cburnett)`. Platform-neutral.

struct ChessPieceView: View {
    let piece: Piece
    var pieceSet: PieceSet = .cburnett

    var body: some View {
        pieceSet.image(for: piece)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}
