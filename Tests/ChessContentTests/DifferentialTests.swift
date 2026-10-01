import Foundation
import Testing

@testable import ChessContent
@testable import ChessCore

/// `ChessPosition` is the rules reference; the search engine's board must agree with it.
@Suite
struct DifferentialTests {
  private static func engineMoves(in position: ChessPosition) -> Set<ChessMove> {
    var board = EngineBoard(position)
    defer { board.deallocate() }
    return Set(board.legalMoves().map(\.chessMove))
  }

  private static func engineInsufficientMaterial(in position: ChessPosition) -> Bool {
    let board = EngineBoard(position)
    defer { board.deallocate() }
    return board.hasInsufficientMaterial
  }

  /// FENs of every disagreement between the two implementations at `position`.
  private static func disagreements(at position: ChessPosition) -> [String] {
    var found: [String] = []
    if Set(position.legalMoves()) != engineMoves(in: position) {
      found.append("legal moves differ at \(position.fen)")
    }
    if position.hasInsufficientMaterial != engineInsufficientMaterial(in: position) {
      found.append("insufficient material differs at \(position.fen)")
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
    var found = disagreements(at: position)
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
      found += disagreements(at: position)
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
      // En passant available, available to a pawn of each side, and not capturable.
      "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2",
      "4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 1",
      "4k3/8/8/8/4P3/8/8/4K3 b - e3 0 1",
      // The capture would expose the black king to the queen along the fourth rank.
      "8/8/8/8/k2Pp2Q/8/8/4K3 b - d3 0 1",
      // Castling with and without the right, and through an attacked square.
      "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
      "r3k2r/8/8/8/8/5q2/8/R3K2R w KQkq - 0 1",
      "r3k2r/8/8/8/8/8/8/R3K2R b Kq - 0 1",
      // Promotions with capture.
      "1n2k3/P7/8/8/8/8/p7/1N2K3 w - - 0 1",
    ]
  )
  func handWrittenPositionsAgree(fen: String) throws {
    #expect(Self.disagreements(at: try ChessPosition(fen: fen)).isEmpty)
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
    let position = try ChessPosition(fen: fen)
    #expect(Self.engineInsufficientMaterial(in: position) == insufficient)
    #expect(position.hasInsufficientMaterial == insufficient)
  }
}
