import ChessCore
import ChessPlay
// Foundation provides `CGPoint`, `CGSize`, and `CGFloat`; unused_import does not attribute them.
// swiftlint:disable:next unused_import
import Foundation

/// The review screen's board position and move browsing, apart from the views.
///
/// A ply is a position of the game: 0 is the start and `n` is the position after `n` moves,
/// so the move played to reach ply `n` is `game.moves[n - 1]`.
enum ReviewLayout {
  enum Step: Equatable {
    case first, previous, next, last
  }

  /// The ply after `step`, kept inside `0...moveCount`.
  static func ply(_ current: Int, step: Step, moveCount: Int) -> Int {
    switch step {
    case .first: 0
    case .previous: max(0, min(current, moveCount) - 1)
    case .next: min(moveCount, max(current, 0) + 1)
    case .last: moveCount
    }
  }

  /// Board input while browsing: left and right step, up and down jump to the ends.
  static func step(for direction: BoardDirection) -> Step {
    switch direction {
    case .left: .previous
    case .right: .next
    case .up: .first
    case .down: .last
    }
  }

  /// The display-only board at `position`, with the move that led to it marked.
  static func snapshot(
    _ position: ChessPosition,
    lastMove: ChessMove?,
    orientation: PieceColor
  ) -> BoardSnapshot {
    let side = position.sideToMove
    let king = Piece(type: .king, color: side)
    let kingSquare = position.board.first { $0.value == king }?.key
    return BoardSnapshot(
      pieces: position.board,
      orientation: orientation,
      focusedSquare: lastMove?.to ?? kingSquare ?? Square(file: 0, rank: 0),
      selectedSquare: nil,
      legalTargets: [],
      lastMove: lastMove,
      checkSquare: position.isInCheck(side) ? kingSquare : nil,
      hint: nil,
      pendingPromotion: nil,
      isInputEnabled: false
    )
  }

  /// The evaluation graph's x of `ply`: the start at the left edge, the last move at the right.
  static func graphX(ply: Int, moveCount: Int, width: CGFloat) -> CGFloat {
    moveCount > 0 ? width * CGFloat(ply) / CGFloat(moveCount) : 0
  }

  /// The evaluation graph's line in `size`: a point per analysed position from
  /// `GameReviewModel.whiteExpectedPoints`, rising as White's chances do.
  static func graphPoints(_ whitePoints: [Double], moveCount: Int, in size: CGSize) -> [CGPoint] {
    whitePoints.enumerated().map { ply, value in
      CGPoint(
        x: graphX(ply: ply, moveCount: moveCount, width: size.width),
        y: size.height * (1 - min(1, max(0, value)))
      )
    }
  }

  /// The ply nearest `x` on a graph `width` wide.
  static func graphPly(atX x: CGFloat, width: CGFloat, moveCount: Int) -> Int {
    guard width > 0 else { return 0 }
    return min(moveCount, max(0, Int((x / width * CGFloat(moveCount)).rounded())))
  }

  /// A row of the move list; a move's ply is the position after it.
  struct Row: Identifiable, Equatable {
    let number: Int
    let whitePly: Int
    let blackPly: Int?
    var id: Int { number }
  }

  static func rows(moveCount: Int) -> [Row] {
    stride(from: 0, to: moveCount, by: 2).map { index in
      Row(
        number: index / 2 + 1,
        whitePly: index + 1,
        blackPly: index + 1 < moveCount ? index + 2 : nil
      )
    }
  }
}
