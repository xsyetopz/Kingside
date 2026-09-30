import ChessCore
import Foundation

// Board focus and selection, owned by a session and projected into `BoardSnapshot`.
// - `focusedSquare` is the remote or keyboard cursor; `moveFocus(_:)` moves it in screen
//   directions (orientation-aware) and stops at the edges.
// - `select(_:in:movableColor:)` picks up a piece or returns `.move` / `.promotion(moves)`.
// - `complete(_:)` records a played move; `cancelSelection()` drops the selection.

/// A screen direction for the board cursor.
public enum BoardDirection: Hashable, Sendable {
    case up, down, left, right
}

enum BoardSelectionAction: Equatable {
    case none
    case move(ChessMove)
    case promotion([ChessMove])
    /// A piece was selected and the chosen square is neither a legal target nor another own piece.
    case illegalTarget
}

struct BoardInteraction: Equatable {
    var focusedSquare = Square(file: 4, rank: 1)
    var selectedSquare: Square?
    var legalMoves: [ChessMove] = []
    var lastMove: ChessMove?
    /// Black at the bottom.
    var isFlipped = false

    var legalTargets: Set<Square> { Set(legalMoves.map(\.to)) }

    mutating func resetFocus(for color: PieceColor) {
        focusedSquare = Square(file: 4, rank: color == .white ? 1 : 6)
    }

    mutating func moveFocus(_ direction: BoardDirection) {
        let delta: (Int, Int)
        switch direction {
        case .left: delta = (isFlipped ? 1 : -1, 0)
        case .right: delta = (isFlipped ? -1 : 1, 0)
        case .up: delta = (0, isFlipped ? -1 : 1)
        case .down: delta = (0, isFlipped ? 1 : -1)
        }
        focusedSquare = Square(
            file: min(7, max(0, focusedSquare.file + delta.0)),
            rank: min(7, max(0, focusedSquare.rank + delta.1))
        )
    }

    mutating func select(_ square: Square, in position: ChessPosition, movableColor: PieceColor) -> BoardSelectionAction {
        guard position.sideToMove == movableColor else { return .none }
        if selectedSquare != nil {
            let candidates = legalMoves.filter { $0.to == square }
            if candidates.count > 1 && candidates.contains(where: { $0.promotion != nil }) {
                return .promotion(candidates)
            }
            if let move = candidates.first { return .move(move) }
            if position[square]?.color == movableColor {
                selectedSquare = square
                legalMoves = position.legalMoves(from: square)
                return .none
            }
            cancelSelection()
            return .illegalTarget
        }
        guard position[square]?.color == movableColor else { return .none }
        selectedSquare = square
        legalMoves = position.legalMoves(from: square)
        return .none
    }

    mutating func complete(_ move: ChessMove) {
        lastMove = move
        focusedSquare = move.to
        cancelSelection()
    }

    mutating func cancelSelection() {
        selectedSquare = nil
        legalMoves = []
    }
}
