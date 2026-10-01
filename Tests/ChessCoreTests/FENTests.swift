import ChessCore
import Testing

@Suite
struct FENTests {
  private let kings = "4k3/8/8/8/8/8/8/4K3"

  @Test(arguments: ["KK", "qk", "KQkqK", "x", "Kq-", "--"])
  func rejectsMalformedCastlingField(_ field: String) {
    #expect(throws: ChessRuleError.invalidFEN) {
      try ChessPosition(fen: "\(kings) w \(field) - 0 1")
    }
  }

  @Test
  func acceptsCastlingSubsetInOrder() throws {
    let position = try ChessPosition(fen: "\(kings) w Kq - 0 1")
    #expect(position.castlingRights == [.whiteKingSide, .blackQueenSide])
  }

  // Each pawn stands in front of the target with its origin square empty, so only the rank is
  // wrong.
  @Test(arguments: [
    "4k3/8/8/8/8/8/4p3/4K3 w - e3 0 1",
    "4k3/4P3/8/8/8/8/8/4K3 b - e6 0 1",
    "4k3/8/8/8/8/4p3/8/4K3 w - e4 0 1",
    "4k3/8/4P3/8/8/8/8/4K3 b - e5 0 1",
  ])
  func rejectsEnPassantRankNotMatchingSideToMove(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test
  func rejectsEnPassantTargetOffBoard() {
    #expect(throws: ChessRuleError.invalidFEN) {
      try ChessPosition(fen: "\(kings) w - i6 0 1")
    }
  }

  @Test
  func acceptsEnPassantOnRankSixForWhiteAndRankThreeForBlack() throws {
    let white = try ChessPosition(fen: "4k3/8/8/4p3/8/8/8/4K3 w - e6 0 1")
    let black = try ChessPosition(fen: "4k3/8/8/8/4P3/8/8/4K3 b - e3 0 1")
    #expect(white.enPassantTarget == Square(algebraic: "e6"))
    #expect(black.enPassantTarget == Square(algebraic: "e3"))
  }

  @Test(arguments: ["x", "1.5", "-1", "+1", "٣"])
  func rejectsMalformedHalfmoveClock(_ clock: String) {
    #expect(throws: ChessRuleError.invalidFEN) {
      try ChessPosition(fen: "\(kings) w - - \(clock) 1")
    }
  }

  @Test(arguments: ["x", "-1", "0", "+1", "٣", "1e1"])
  func rejectsMalformedFullmoveNumber(_ number: String) {
    #expect(throws: ChessRuleError.invalidFEN) {
      try ChessPosition(fen: "\(kings) w - - 0 \(number)")
    }
  }

  @Test
  func acceptsZeroHalfmoveAndFullmoveOne() throws {
    let position = try ChessPosition(fen: "\(kings) w - - 0 1")
    #expect(position.halfmoveClock == 0)
    #expect(position.fullmoveNumber == 1)
  }

  @Test(arguments: [
    "8/8/8/8/8/8/8/4K3 w - - 0 1",
    "4k3/8/8/8/8/8/8/8 w - - 0 1",
    "4k2k/8/8/8/8/8/8/4K3 w - - 0 1",
    "4k3/8/8/8/8/8/8/3KK3 w - - 0 1",
  ])
  func rejectsAnythingButOneKingPerSide(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test
  func acceptsBareKings() throws {
    let position = try ChessPosition(fen: "\(kings) w - - 0 1")
    #expect(position.board.count == 2)
  }

  @Test(arguments: [
    "4k3/8/8/3PK3/8/8/8/8 w - e6 0 1",
    "4k3/8/4N3/3Pp3/8/8/8/4K3 w - e6 0 1",
    "4k3/4p3/8/4p3/8/8/8/4K3 w - e6 0 1",
    "4k3/4p3/4p3/8/8/8/8/4K3 w - e6 0 1",
    "4k3/8/8/8/8/8/8/4K3 w - e6 0 1",
    "4k3/8/8/8/4P3/4N3/8/4K3 b - e3 0 1",
    "4k3/8/8/4P3/8/8/8/4K3 w - e6 0 1",
  ])
  func rejectsEnPassantTargetWithoutDoublePushedPawn(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test
  func acceptsEnPassantAfterDoublePush() throws {
    let position = try ChessPosition(
      fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    )
    #expect(position.enPassantTarget == Square(algebraic: "e3"))
  }

  @Test
  func rejectsSideNotToMoveInCheck() {
    #expect(throws: ChessRuleError.invalidFEN) {
      try ChessPosition(fen: "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1")
    }
  }

  @Test
  func acceptsSideToMoveInCheck() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
    #expect(position.isInCheck(.white))
  }

  @Test(arguments: [
    "4k3/8/8/8/8/8/8/R3K3 w - - 9223372036854775807 1",
    "4k3/8/8/8/8/8/8/R3K3 b - - 0 9223372036854775807",
    "4k3/8/8/8/8/8/8/R3K3 w - - 9223372036854775808 1",
  ])
  func rejectsClocksThatOverflowWhenIncremented(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test
  func acceptsLargestIncrementableClocks() throws {
    let position = try ChessPosition(fen: "\(kings) b - - 9223372036854775806 9223372036854775806")
    #expect(position.halfmoveClock == Int.max - 1)
    #expect(position.fullmoveNumber == Int.max - 1)
  }

  @Test(arguments: [
    "4k3/8/8/8/8/8/8/٤K٣ w - - 0 1",
    "4k3/8/8/8/8/8/8/04K3 w - - 0 1",
    "4k3/8/8/8/8/8/8/4K21 w - - 0 1",
    "4k3/8/8/8/8/8/8/9 w - - 0 1",
    "4k3/8/8/8/8/8/8/3K w - - 0 1",
    "4k3/8/8/8/8/8/8/5K3 w - - 0 1",
    "4k3/8/8/8/8/8/8/K w - - 0 1",
  ])
  func rejectsMalformedBoardRank(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test
  func rejectsNonASCIIPieceLetter() {
    // U+212A KELVIN SIGN lowercases to an ASCII "k".
    #expect(throws: ChessRuleError.invalidFEN) {
      try ChessPosition(fen: "4k3/8/8/8/8/8/8/4\u{212A}3 w - - 0 1")
    }
  }

  @Test
  func rejectsMoreThanSixFields() {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: "\(kings) w - - 0 1 x") }
  }

  // The first position has 263 pseudo-legal White moves, more than the engine's 256-entry move
  // list per ply holds.
  @Test(arguments: [
    "QQQQQQrk/Q4Qrr/Q5QQ/Q6Q/Q6Q/Q6Q/Q6Q/KQQQQQQQ w - - 0 1",
    "4k3/8/8/8/8/8/PPPPPPPP/QQBQKBNR w - - 0 1",
  ])
  func rejectsMorePromotedPiecesThanMissingPawns(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test(arguments: [
    "4k3/8/8/8/8/P7/PPPPPPPP/4K3 w - - 0 1",
    "4k3/pppppppp/p7/8/8/8/8/4K3 w - - 0 1",
  ])
  func rejectsMoreThanEightPawnsPerSide(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test(arguments: ["4k3/8/8/8/8/8/8/P3K3 w - - 0 1", "p3k3/8/8/8/8/8/8/4K3 w - - 0 1"])
  func rejectsPawnOnBackRank(_ fen: String) {
    #expect(throws: ChessRuleError.invalidFEN) { try ChessPosition(fen: fen) }
  }

  @Test
  func acceptsSixteenPiecesWithOnePromotedQueen() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/Q7/PPPPPPP1/RNBQKBNR w - - 0 1")
    #expect(position.board.count == 17)
  }
}
