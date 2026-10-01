import ChessCore
import Testing

@Suite
struct ChessGameTests {
  private static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  private static let afterE4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

  private func play(_ ucis: [String]) throws -> ChessGame {
    var game = ChessGame()
    for uci in ucis { try game.makeMove(move(uci)) }
    return game
  }

  @Test
  func undoRestoresPreviousPosition() throws {
    var game = try play(["e2e4", "e7e5"])
    game.undo()
    #expect(game.position.fen == Self.afterE4FEN)
    #expect(game.moves.map(\.san) == ["e4"])
  }

  @Test
  func undoReturnsTheRemovedMove() throws {
    var game = try play(["e2e4", "e7e5"])
    let removed = game.undo()
    #expect(removed?.san == "e5")
    #expect(removed?.move == (try move("e7e5")))
  }

  @Test
  func undoOnEmptyGameDoesNothing() {
    var game = ChessGame()
    #expect(game.undo() == nil)
    #expect(game.position.fen == Self.startFEN)
  }

  @Test
  func restartReturnsToStartingPosition() throws {
    var game = try play(["e2e4", "e7e5", "g1f3"])
    game.restart()
    #expect(game.position.fen == Self.startFEN)
    #expect(game.moves.isEmpty)
  }

  @Test
  func restartReturnsToCustomStartingPosition() throws {
    let fen = "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"
    var game = ChessGame(position: try ChessPosition(fen: fen))
    try game.makeMove(move("a1a2"))
    game.restart()
    #expect(game.position.fen == fen)
    #expect(game.moves.isEmpty)
  }

  @Test
  func initWithMovesTakesInitialPositionFromFirstMove() throws {
    let line = [
      PlayedMove(
        move: try move("e2e4"),
        san: "e4",
        positionBefore: try ChessPosition(fen: Self.startFEN)
      ),
      PlayedMove(
        move: try move("e7e5"),
        san: "e5",
        positionBefore: try ChessPosition(fen: Self.afterE4FEN)
      ),
    ]
    let current = try ChessPosition(
      fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
    )
    let game = ChessGame(position: current, moves: line)
    #expect(game.initialPosition.fen == Self.startFEN)
    #expect(game.moves.map(\.san) == ["e4", "e5"])
    #expect(game.position.fen == current.fen)
  }

  @Test
  func restartAfterInitWithMovesReturnsToFirstMovePosition() throws {
    let line = [
      PlayedMove(
        move: try move("e2e4"),
        san: "e4",
        positionBefore: try ChessPosition(fen: Self.startFEN)
      )
    ]
    var game = ChessGame(position: try ChessPosition(fen: Self.afterE4FEN), moves: line)
    game.restart()
    #expect(game.position.fen == Self.startFEN)
  }

  @Test
  func makeMoveRecordsHandWrittenLine() throws {
    let game = try play(["e2e4", "e7e5", "g1f3"])
    #expect(game.moves.map(\.san) == ["e4", "e5", "Nf3"])
    #expect(
      game.position.fen == "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2"
    )
  }
}

@Suite
struct MoveCounterTests {
  private func after(_ fen: String, _ uci: String) throws -> ChessPosition {
    try ChessPosition(fen: fen).applying(move(uci))
  }

  @Test
  func halfmoveClockReachingOneHundredIsFiftyMoveDraw() throws {
    let next = try after("4k3/8/8/8/8/8/8/R3K3 w - - 99 60", "a1a2")
    #expect(next.halfmoveClock == 100)
    #expect(next.outcome == .drawFiftyMove)
    #expect(next.outcome.isDraw)
  }

  @Test
  func halfmoveClockBelowOneHundredIsOngoing() throws {
    let next = try after("4k3/8/8/8/8/8/8/R3K3 w - - 98 60", "a1a2")
    #expect(next.halfmoveClock == 99)
    #expect(next.outcome == .ongoing)
  }

  @Test
  func gameReportsFiftyMoveDraw() throws {
    var game = ChessGame(position: try ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 99 60"))
    try game.makeMove(move("a1a2"))
    #expect(game.outcome == .drawFiftyMove)
  }

  @Test
  func pawnMoveResetsHalfmoveClock() throws {
    let next = try after("4k3/8/8/8/8/8/P7/R3K3 w - - 99 60", "a2a3")
    #expect(next.halfmoveClock == 0)
    #expect(next.outcome == .ongoing)
  }

  @Test
  func captureResetsHalfmoveClock() throws {
    let next = try after("4k3/8/8/8/r7/8/8/R3K3 w - - 99 60", "a1a4")
    #expect(next.halfmoveClock == 0)
  }

  @Test
  func quietPieceMoveIncrementsHalfmoveClock() throws {
    #expect(try after("4k3/8/8/8/8/8/8/R3K3 w - - 7 60", "a1a2").halfmoveClock == 8)
  }

  @Test
  func fullmoveNumberIncrementsAfterBlackMove() throws {
    #expect(try after("4k3/8/8/8/8/8/8/R3K3 b - - 0 7", "e8d8").fullmoveNumber == 8)
  }

  @Test
  func fullmoveNumberStaysAfterWhiteMove() throws {
    #expect(try after("4k3/8/8/8/8/8/8/R3K3 w - - 0 7", "a1a2").fullmoveNumber == 7)
  }
}
