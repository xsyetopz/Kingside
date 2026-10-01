import ChessCore
import Testing

@Suite
struct RepetitionTests {
  private let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]

  /// Black plays d7d5, then both knights shuffle out and back twice, so the position after d5
  /// recurs twice more without its en-passant target.
  private func gameAfterDoublePushAndTwoShuffles(fen: String) throws -> ChessGame {
    var game = ChessGame(position: try ChessPosition(fen: fen))
    try game.makeMove(move("d7d5"))
    for uci in shuffle + shuffle { try game.makeMove(move(uci)) }
    return game
  }

  @Test
  func aLegalEnPassantCaptureMakesThePositionDifferent() throws {
    let game = try gameAfterDoublePushAndTwoShuffles(fen: "4k1n1/3p4/8/4P3/8/8/8/4K1N1 b - - 0 1")
    #expect(game.outcome == .ongoing)
  }

  @Test
  func anEnPassantCaptureThatExposesTheKingDoesNotCount() throws {
    let game = try gameAfterDoublePushAndTwoShuffles(fen: "4k1n1/3p4/8/K3P2r/8/8/8/6N1 b - - 0 1")
    #expect(game.outcome == .drawThreefoldRepetition)
  }
}
