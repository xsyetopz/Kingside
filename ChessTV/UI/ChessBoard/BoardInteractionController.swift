import SwiftUI
import ChessCore

enum BoardSelectionAction {
    case none
    case move(ChessMove)
    case promotion([ChessMove])
}

@MainActor
final class BoardInteractionController: ObservableObject {
    @Published var focusedSquare = Square(file: 4, rank: 1)
    @Published var selectedSquare: Square?
    @Published var legalMoves: [ChessMove] = []
    @Published var lastMove: ChessMove?
    var isFlipped = false

    var legalDestinations: Set<Square> { Set(legalMoves.map(\.to)) }

    func resetFocus(for color: PieceColor) {
        focusedSquare = Square(file: 4, rank: color == .white ? 1 : 6)
    }

    func moveFocus(_ direction: MoveCommandDirection) {
        let delta: (Int, Int)
        switch direction {
        case .left: delta = (isFlipped ? 1 : -1, 0)
        case .right: delta = (isFlipped ? -1 : 1, 0)
        case .up: delta = (0, isFlipped ? -1 : 1)
        case .down: delta = (0, isFlipped ? 1 : -1)
        @unknown default: return
        }
        focusedSquare = Square(
            file: min(7, max(0, focusedSquare.file + delta.0)),
            rank: min(7, max(0, focusedSquare.rank + delta.1))
        )
    }

    func selectFocused(in position: ChessPosition, movableColor: PieceColor) -> BoardSelectionAction {
        select(focusedSquare, in: position, movableColor: movableColor)
    }

    func select(_ square: Square, in position: ChessPosition, movableColor: PieceColor) -> BoardSelectionAction {
        guard position.sideToMove == movableColor else { return .none }
        if selectedSquare != nil {
            let candidates = legalMoves.filter { $0.to == square }
            if candidates.count > 1 && candidates.contains(where: { $0.promotion != nil }) {
                return .promotion(candidates)
            }
            if let move = candidates.first { return .move(move) }
            if position[square]?.color == movableColor {
                self.selectedSquare = square
                legalMoves = position.legalMoves(from: square)
                return .none
            }
            cancelSelection()
            return .none
        }
        guard position[square]?.color == movableColor else { return .none }
        selectedSquare = square
        legalMoves = position.legalMoves(from: square)
        return .none
    }

    func complete(_ move: ChessMove) {
        lastMove = move
        focusedSquare = move.to
        cancelSelection()
    }

    func cancelSelection() {
        selectedSquare = nil
        legalMoves = []
    }
}
