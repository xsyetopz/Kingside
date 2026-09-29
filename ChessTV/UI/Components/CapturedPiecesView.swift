import SwiftUI
import ChessCore

// Captured material strip: `CapturedPiecesView(captured: [.pawn, .pawn, .knight], color: .black, advantage: 2)`.
// `captured` are the taken piece types, drawn in `color` (the side that lost them), grouped by
// type (pawns first) with pieces in a group overlapping. A positive `advantage` adds "+N".

struct CapturedPiecesView: View {
    let captured: [PieceType]
    let color: PieceColor
    let advantage: Int
    var pieceSize: CGFloat = 34
    var pieceSet: PieceSet = .cburnett

    private static let order: [PieceType] = [.pawn, .knight, .bishop, .rook, .queen, .king]

    var body: some View {
        HStack(spacing: pieceSize * 0.2) {
            ForEach(Self.order, id: \.self) { type in
                let count = captured.filter { $0 == type }.count
                if count > 0 {
                    HStack(spacing: -pieceSize * 0.6) {
                        ForEach(0..<count, id: \.self) { _ in
                            ChessPieceView(piece: Piece(type: type, color: color), pieceSet: pieceSet)
                                .frame(width: pieceSize, height: pieceSize)
                        }
                    }
                }
            }
            if advantage > 0 {
                Text("+\(advantage)")
                    .font(.system(size: pieceSize * 0.72, weight: .semibold))
                    .foregroundStyle(ChessTheme.textSecondary)
                    .padding(.leading, pieceSize * 0.1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let list = captured.map(\.rawValue).joined(separator: ", ")
        let base = captured.isEmpty ? "No captured pieces" : "Captured \(list)"
        return advantage > 0 ? "\(base), plus \(advantage)" : base
    }
}
