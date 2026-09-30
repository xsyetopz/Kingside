import Testing

@testable import ChessCore

func move(_ uci: String) throws -> ChessMove { try #require(ChessMove(uci: uci)) }
func square(_ name: String) throws -> Square { try #require(Square(algebraic: name)) }

@Suite
struct ChessRulesTests {
  @Test
  func initialPositionHasTwentyMoves() {
    #expect(ChessPosition.initial.legalMoves().count == 20)
  }

  @Test
  func normalMoveAndCapture() throws {
    var game = ChessGame()
    for uci in ["e2e4", "d7d5", "e4d5"] { try game.makeMove(move(uci)) }
    #expect(game.position[try square("d5")] == Piece(type: .pawn, color: .white))
    #expect(game.position[try square("e4")] == nil)
  }

  @Test
  func illegalMoveRejected() throws {
    let illegal = try move("e2e5")
    #expect(throws: (any Error).self) { try ChessPosition.initial.applying(illegal) }
  }

  @Test
  func pinnedPieceCannotExposeKing() throws {
    let position = try ChessPosition(fen: "4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1")
    #expect(!position.legalMoves().contains(try move("e2d2")))
    #expect(position.legalMoves().contains(try move("e2e8")))
  }

  @Test
  func castlingMovesRook() throws {
    let position = try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let next = try position.applying(move("e1g1"))
    #expect(next[try square("f1")] == Piece(type: .rook, color: .white))
    #expect(next[try square("g1")] == Piece(type: .king, color: .white))
  }

  @Test
  func cannotCastleThroughCheck() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/2b5/8/8/4K2R w K - 0 1")
    #expect(!position.legalMoves().contains(try move("e1g1")))
  }

  @Test
  func enPassant() throws {
    var position = try ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")
    try position.apply(move("e5d6"))
    #expect(position[try square("d5")] == nil)
    #expect(position[try square("d6")] == Piece(type: .pawn, color: .white))
  }

  @Test
  func promotion() throws {
    let position = try ChessPosition(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    let next = try position.applying(move("a7a8q"))
    #expect(next[try square("a8")]?.type == .queen)
    #expect(next.halfmoveClock == 0)
  }

  @Test
  func foolsMateCheckmate() throws {
    var game = ChessGame()
    for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] { try game.makeMove(move(uci)) }
    #expect(game.position.outcome == .checkmate(winner: .black))
  }

  @Test
  func stalemate() throws {
    let position = try ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    #expect(position.outcome == .stalemate)
  }

  @Test
  func threefoldRepetitionByKnightShuffles() throws {
    var game = ChessGame()
    let cycle = ["g1f3", "g8f6", "f3g1", "f6g8"]
    for uci in cycle { try game.makeMove(move(uci)) }
    #expect(game.outcome == .ongoing)
    for uci in cycle.dropLast() { try game.makeMove(move(uci)) }
    #expect(game.outcome == .ongoing)
    try game.makeMove(move("f6g8"))
    #expect(game.outcome == .drawThreefoldRepetition)
    #expect(game.outcome.isDraw)
    #expect(game.position.outcome == .ongoing)
  }

  @Test
  func repetitionRequiresSameCastlingRights() throws {
    var game = ChessGame(
      position: try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    )
    for uci in ["a1b1", "a8b8", "b1a1", "b8a8", "a1b1", "a8b8", "b1a1", "b8a8"] {
      try game.makeMove(move(uci))
    }
    #expect(game.outcome == .ongoing)
  }

  @Test(arguments: [
    "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
    "4k3/8/8/8/8/8/8/3BK3 w - - 0 1",
    "4k3/8/8/8/8/8/8/3NK3 w - - 0 1",
    "2b1k3/8/8/8/8/8/8/3BK3 w - - 0 1",
  ])
  func insufficientMaterialDraws(fen: String) throws {
    let outcome = try ChessPosition(fen: fen).outcome
    #expect(outcome == .drawInsufficientMaterial)
    #expect(outcome.isDraw)
  }

  @Test(arguments: [
    "4kb2/8/8/8/8/8/8/3BK3 w - - 0 1",  // opposite-color bishops
    "4k3/8/8/8/8/8/P7/4K3 w - - 0 1",
    "4k3/8/8/8/8/8/8/2NNK3 w - - 0 1",
  ])
  func sufficientMaterialIsNotDraw(fen: String) throws {
    #expect(try ChessPosition(fen: fen).outcome == .ongoing)
  }

  @Test
  func doubleCheckAllowsOnlyKingMoves() throws {
    let position = try ChessPosition(fen: "4k3/8/8/1B6/8/8/4R3/4K3 b - - 0 1")
    #expect(position.isInCheck(.black))
    #expect(position.legalMoves().allSatisfy { position[$0.from]?.type == .king })
  }

  @Test
  func discoveredCheck() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4B3/4R1K1 w - - 0 1")
    #expect(try position.applying(move("e2b5")).isInCheck(.black))
  }

  @Test
  func kingCannotMoveIntoCheck() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/3r4/4K3 w - - 0 1")
    #expect(!position.legalMoves().contains(try move("e1d1")))
  }
}
