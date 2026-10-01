import ChessCore
import Testing

@Suite
struct NotationTests {
  private func san(_ fen: String, _ uci: String) throws -> String {
    try ChessNotation.san(for: move(uci), in: ChessPosition(fen: fen))
  }

  @Test
  func disambiguatesByFile() throws {
    #expect(try san("4k3/8/8/8/8/8/4K3/R6R w - - 0 1", "a1d1") == "Rad1")
  }

  @Test
  func disambiguatesByRank() throws {
    #expect(try san("4k3/8/8/R7/8/8/8/R3K3 w - - 0 1", "a1a3") == "R1a3")
  }

  @Test
  func disambiguatesByFileAndRankWithThreeQueens() throws {
    #expect(try san("8/k7/7K/8/1Q5Q/8/8/7Q w - - 0 1", "h4e1") == "Qh4e1")
  }

  @Test
  func promotionAppendsPieceLetter() throws {
    #expect(try san("8/P7/6k1/8/8/8/8/4K3 w - - 0 1", "a7a8q") == "a8=Q")
  }

  @Test
  func checkAppendsPlus() throws {
    #expect(try san("4k3/8/8/8/8/8/8/4K2R w - - 0 1", "h1h8") == "Rh8+")
  }

  @Test
  func checkmateAppendsHash() throws {
    #expect(try san("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", "a1a8") == "Ra8#")
  }

  @Test
  func queensideCastling() throws {
    #expect(try san("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1c1") == "O-O-O")
  }

  @Test
  func kingsideCastling() throws {
    #expect(try san("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1") == "O-O")
  }

  @Test
  func enPassantCaptureNamesOriginFile() throws {
    #expect(try san("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2", "e5d6") == "exd6")
  }

  @Test
  func illegalMoveHasNoSAN() {
    #expect(throws: (any Error).self) { try san("4k3/8/8/8/8/8/8/4K3 w - - 0 1", "e1e3") }
  }

  @Test
  func parsesZeroZeroAsCastling() throws {
    let position = try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    #expect(ChessNotation.move(fromSAN: "0-0", in: position) == (try move("e1g1")))
  }

  @Test
  func parsesZeroZeroZeroAsQueensideCastling() throws {
    let position = try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    #expect(ChessNotation.move(fromSAN: "0-0-0", in: position) == (try move("e1c1")))
  }

  @Test
  func parsesExclamationAnnotation() throws {
    #expect(ChessNotation.move(fromSAN: "e4!", in: .initial) == (try move("e2e4")))
  }

  @Test
  func parsesQuestionExclamationAnnotation() throws {
    #expect(ChessNotation.move(fromSAN: "Nf3?!", in: .initial) == (try move("g1f3")))
  }

  @Test
  func parsesCheckmateSuffix() throws {
    let position = try ChessPosition(
      fen: "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
    )
    #expect(ChessNotation.move(fromSAN: "Qxf7#", in: position) == (try move("f3f7")))
  }

  @Test
  func unknownSANParsesToNil() {
    #expect(ChessNotation.move(fromSAN: "Ke4", in: .initial) == nil)
  }
}
