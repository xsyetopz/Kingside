import ChessCore
import Foundation
import Testing

@Suite
struct ChessPositionStorageTests {
  private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  private let afterE4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

  @Test
  func applyingToACopyLeavesTheOriginalUnchanged() throws {
    let original = try ChessPosition(fen: startFEN)
    var copy = original
    try copy.apply(move("e2e4"))
    #expect(original == (try ChessPosition(fen: startFEN)))
    #expect(original.fen == startFEN)
    #expect(original[try #require(Square(algebraic: "e2"))] == Piece(type: .pawn, color: .white))
    #expect(copy.fen == afterE4FEN)
  }

  @Test
  func applyingToTheOriginalLeavesACopyUnchanged() throws {
    var original = try ChessPosition(fen: startFEN)
    let copy = original
    try original.apply(move("e2e4"))
    #expect(copy == (try ChessPosition(fen: startFEN)))
    #expect(copy.fen == startFEN)
    #expect(copy.legalMoves().count == 20)
    #expect(original.fen == afterE4FEN)
  }

  @Test
  func appliedPositionEqualsTheSamePositionParsedFromFEN() throws {
    var position = ChessPosition.initial
    try position.apply(move("g1f3"))
    try position.apply(move("b8c6"))
    #expect(position == (try ChessPosition(fen: position.fen)))
    let parsed = try ChessPosition(
      fen: "r1bqkbnr/pppppppp/2n5/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 2 2"
    )
    #expect(position == parsed)
  }

  @Test
  func doublePushKeepsAnUncapturableEnPassantTarget() throws {
    let pushed = try ChessPosition.initial.applying(move("e2e4"))
    #expect(pushed.enPassantTarget == Square(algebraic: "e3"))
    #expect(pushed == (try ChessPosition(fen: afterE4FEN)))
    let withoutTarget = afterE4FEN.replacingOccurrences(of: " e3 ", with: " - ")
    #expect(pushed != (try ChessPosition(fen: withoutTarget)))
  }

  @Test
  func jsonRoundTripKeepsThePosition() throws {
    let position = try ChessPosition(
      fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 3 17"
    )
    let data = try JSONEncoder().encode(position)
    #expect(try JSONDecoder().decode(String.self, from: data) == position.fen)
    #expect(try JSONDecoder().decode(ChessPosition.self, from: data) == position)
  }

  @Test
  func decodingAnInvalidFENThrows() throws {
    let data = try JSONEncoder().encode("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1")
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ChessPosition.self, from: data) }
  }

  @Test
  func kinglessPositionHasNoLegalMovesButAnswersAttacks() throws {
    let rook = try #require(Square(algebraic: "a1"))
    let position = ChessPosition(board: [rook: Piece(type: .rook, color: .white)])
    #expect(position.legalMoves().isEmpty)
    #expect(position.isSquareAttacked(try #require(Square(algebraic: "a8")), by: .white))
    #expect(position.isSquareAttacked(try #require(Square(algebraic: "h1")), by: .white))
    #expect(!position.isSquareAttacked(try #require(Square(algebraic: "b2")), by: .white))
    #expect(!position.isSquareAttacked(try #require(Square(algebraic: "a8")), by: .black))
  }

  @Test
  func halfmoveClockSaturatesInsteadOfOverflowing() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 9223372036854775806 1")
      .applying(move("a1a2")).applying(move("e8e7"))
    #expect(position.halfmoveClock == Int.max)
    #expect(position.fullmoveNumber == 2)
  }

  @Test
  func fullmoveNumberSaturatesInsteadOfOverflowing() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 b - - 0 9223372036854775806")
      .applying(move("e8e7")).applying(move("a1a2")).applying(move("e7e6"))
    #expect(position.fullmoveNumber == Int.max)
    #expect(position.halfmoveClock == 3)
  }
}
