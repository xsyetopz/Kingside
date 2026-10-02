import Testing

@testable import ChessContent
@testable import ChessCore

/// Every catalog position reached by `apply` must equal the same position parsed from its FEN,
/// with the same legal moves.
@Suite
struct DifferentialTests {
  /// FENs of every mismatch between `position` and `ChessPosition(fen: position.fen)`.
  private static func disagreements(at position: ChessPosition) throws -> [String] {
    let parsed = try ChessPosition(fen: position.fen)
    var found: [String] = []
    if position != parsed {
      found.append("position differs from its FEN at \(position.fen)")
    }
    if Set(position.legalMoves()) != Set(parsed.legalMoves()) {
      found.append("legal moves differ from its FEN at \(position.fen)")
    }
    return found
  }

  /// Plays `moves` from `start`, checking each position, and that a double pawn push leaves the
  /// FEN en-passant target (the skipped square) and any other move leaves none.
  private static func disagreements(
    playing moves: [ChessMove],
    from start: ChessPosition
  ) throws -> [String] {
    var position = start
    var found = try disagreements(at: position)
    for move in moves {
      let isDoublePush =
        position[move.from]?.type == .pawn && abs(move.to.rank - move.from.rank) == 2
      try position.apply(move)
      let expected =
        isDoublePush
        ? Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2) : nil
      if position.enPassantTarget != expected {
        found.append("en-passant target is not FEN-style at \(position.fen)")
      }
      found += try disagreements(at: position)
    }
    return found
  }

  @Test
  func puzzlePositionsAgree() throws {
    let puzzles = try ContentCatalog.load().puzzles
    var found: [String] = []
    for puzzle in puzzles {
      found += try Self.disagreements(playing: puzzle.moves, from: puzzle.initialPosition())
    }
    #expect(!puzzles.isEmpty)
    #expect(found.isEmpty, "\(found.prefix(5))")
  }

  @Test
  func openingBookPositionsAgree() throws {
    let lines = try ContentCatalog.load().openingBook.lines
    var found: [String] = []
    for line in lines {
      var position = ChessPosition.initial
      var moves: [ChessMove] = []
      for san in line.split(separator: " ") {
        let move = try #require(ChessNotation.move(fromSAN: String(san), in: position))
        moves.append(move)
        position = try position.applying(move)
      }
      found += try Self.disagreements(playing: moves, from: .initial)
    }
    #expect(!lines.isEmpty)
    #expect(found.isEmpty, "\(found.prefix(5))")
  }

  @Test(
    arguments: [
      ("4k3/8/8/8/8/8/8/4K3 w - - 0 1", true),
      ("4k3/8/8/8/8/8/8/3BK3 w - - 0 1", true),
      ("4k3/8/8/8/8/8/8/3NK3 w - - 0 1", true),
      ("4k3/8/8/8/8/8/8/2NNK3 w - - 0 1", false),
      ("4k3/8/8/8/8/8/8/2BBK3 w - - 0 1", false),
      ("4k3/8/8/8/8/8/P7/4K3 w - - 0 1", false),
      // c1 and f8 are both dark squares; c1 and c8 are not.
      ("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1", true),
      ("2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1", false),
      // Bishop and knight against a bishop of the same color is still mating material.
      ("4kb2/8/8/8/8/8/8/2BNK3 w - - 0 1", false),
      // Two bishops of one color on the same side can mate.
      ("4k3/8/8/8/8/4B3/8/2B1K3 w - - 0 1", false),
    ]
  )
  func insufficientMaterialMatchesTheRules(fen: String, insufficient: Bool) throws {
    #expect(try ChessPosition(fen: fen).hasInsufficientMaterial == insufficient)
  }
}
