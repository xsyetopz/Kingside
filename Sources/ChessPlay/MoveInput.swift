import ChessCore
import Foundation

// The player's move input on one board, shared by `GameSession`, `OnlineGameSession` and
// `PuzzleBoardSession`.
// - `select(_:in:movableColor:autoQueen:)` picks up a piece or returns the move to play; a
//   promotion opens the picker unless `autoQueen` plays the queen.
// - `promote(_:)` closes the picker with the chosen move; `cancel()` drops the picker and the
//   selection; `complete(_:)` records a played move.
// - `snapshot(of:canMove:hint:badge:)` is the only place a `BoardSnapshot` is built.

/// Selection, promotion picker, focus and orientation of a board, and its `BoardSnapshot`.
struct MoveInput: Equatable {
  /// What a session does after `select(_:in:movableColor:autoQueen:)`.
  enum Outcome: Equatable {
    case none
    case play(ChessMove)
    /// A piece was selected and the chosen square is neither a legal target nor another own piece.
    case illegalTarget
  }

  private var board = BoardInteraction()
  /// Promotion moves waiting for `promote(_:)`; empty when no picker is shown.
  private var promotionMoves: [ChessMove] = []

  /// Black at the bottom.
  var isFlipped: Bool {
    get { board.isFlipped }
    set { board.isFlipped = newValue }
  }
  var focusedSquare: Square { board.focusedSquare }
  var lastMove: ChessMove? {
    get { board.lastMove }
    set { board.lastMove = newValue }
  }
  var isChoosingPromotion: Bool { !promotionMoves.isEmpty }
  /// True when `cancel()` would close the promotion picker or drop a selection.
  var hasCancellableSelection: Bool { isChoosingPromotion || board.selectedSquare != nil }

  mutating func moveFocus(_ direction: BoardDirection) { board.moveFocus(direction) }

  mutating func focus(_ square: Square) { board.focusedSquare = square }

  mutating func resetFocus(for color: PieceColor) { board.resetFocus(for: color) }

  mutating func select(
    _ square: Square,
    in position: ChessPosition,
    movableColor: PieceColor,
    autoQueen: Bool
  ) -> Outcome {
    switch board.select(square, in: position, movableColor: movableColor) {
    case .none: return .none
    case .illegalTarget: return .illegalTarget
    case .move(let move): return .play(move)
    case .promotion(let moves):
      if autoQueen, let queen = moves.first(where: { $0.promotion == .queen }) {
        return .play(queen)
      }
      promotionMoves = moves
      return .none
    }
  }

  /// The pending promotion move to `type`, closing the picker; nil when no such move waits.
  mutating func promote(_ type: PieceType) -> ChessMove? {
    guard let move = promotionMoves.first(where: { $0.promotion == type }) else { return nil }
    promotionMoves = []
    return move
  }

  mutating func cancel() {
    promotionMoves = []
    board.cancelSelection()
  }

  mutating func complete(_ move: ChessMove) {
    promotionMoves = []
    board.complete(move)
  }

  /// The board as drawn; input is disabled while the picker is open or when `canMove` is false.
  func snapshot(
    of position: ChessPosition,
    canMove: Bool,
    hint: BoardArrow? = nil,
    badge: SquareBadge? = nil
  ) -> BoardSnapshot {
    let side = position.sideToMove
    let king = Piece(type: .king, color: side)
    return BoardSnapshot(
      pieces: position.board,
      orientation: board.isFlipped ? .black : .white,
      focusedSquare: board.focusedSquare,
      selectedSquare: board.selectedSquare,
      legalTargets: board.legalTargets,
      lastMove: board.lastMove,
      checkSquare: position.isInCheck(side) ? position.board.first { $0.value == king }?.key : nil,
      hint: hint,
      pendingPromotion: promotionMoves.first.map { move in
        PendingPromotion(
          from: move.from,
          to: move.to,
          color: side,
          choices: promotionMoves.compactMap(\.promotion)
        )
      },
      isInputEnabled: canMove && promotionMoves.isEmpty,
      badge: badge
    )
  }
}
