import ChessContent
import ChessCore
import Foundation

/// Pure formatting of game state for display.
enum GamePresentation {
  static func moveRows(_ moves: [PlayedMove]) -> [MoveRow] {
    stride(from: 0, to: moves.count, by: 2).map { index in
      MoveRow(
        number: index / 2 + 1,
        white: moves[index].san,
        black: index + 1 < moves.count ? moves[index + 1].san : nil
      )
    }
  }

  static func materialAdvantage(in position: ChessPosition) -> [PieceColor: Int] {
    let difference = Material.points(.white, in: position) - Material.points(.black, in: position)
    return [.white: max(0, difference), .black: max(0, -difference)]
  }

  static func resultTitle(
    _ result: GameResult,
    humanColor: PieceColor?,
    localization: Localization
  ) -> String {
    GameSession.resultTitleKey(result, humanColor: humanColor).map { localization.string($0) } ?? ""
  }

  static func turnText(
    sideToMove: PieceColor,
    humanColor: PieceColor?,
    inCheck: Bool,
    localization: Localization
  ) -> String {
    let base = localization.string(turnTextKey(sideToMove: sideToMove, humanColor: humanColor))
    return inCheck ? localization.string("game.turn.check", base) : base
  }

  static func turnTextKey(sideToMove: PieceColor, humanColor: PieceColor?) -> String {
    if let humanColor { return sideToMove == humanColor ? "game.turn.yours" : "game.turn.opponent" }
    return sideToMove == .white ? "game.turn.white" : "game.turn.black"
  }

  static func seconds(_ duration: Duration) -> TimeInterval {
    let parts = duration.components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}
