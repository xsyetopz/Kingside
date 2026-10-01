import ChessCore
import Testing

@testable import ChessBoardScene

@Suite
struct PieceDiffTests {
  private static func square(_ name: String) -> Square { Square(algebraic: name)! }

  private static func board(_ fen: String) throws -> [Square: Piece] {
    try ChessPosition(fen: fen).board
  }

  private static func diff(
    from old: String,
    to new: String,
    lastMove: String?
  ) throws -> PieceDiff {
    PieceDiff(
      old: try board(old),
      new: try board(new),
      lastMove: try lastMove.map { try #require(ChessMove(uci: $0)) }
    )
  }

  private static func move(
    _ from: String,
    _ to: String,
    _ type: PieceType,
    _ color: PieceColor
  ) -> PieceDiff.Move {
    PieceDiff.Move(from: square(from), to: square(to), piece: Piece(type: type, color: color))
  }

  @Test
  func plainMoveSlidesThePiece() throws {
    let diff = try Self.diff(
      from: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      to: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
      lastMove: "e2e4"
    )
    #expect(diff.moved == [Self.move("e2", "e4", .pawn, .white)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed.isEmpty)
  }

  @Test
  func captureRemovesTheCapturedPiece() throws {
    let diff = try Self.diff(
      from: "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
      to: "rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2",
      lastMove: "e4d5"
    )
    #expect(diff.moved == [Self.move("e4", "d5", .pawn, .white)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed == [Self.square("d5")])
  }

  @Test
  func castlingSlidesKingAndRook() throws {
    let diff = try Self.diff(
      from: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
      to: "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1",
      lastMove: "e1g1"
    )
    #expect(
      diff.moved == [Self.move("e1", "g1", .king, .white), Self.move("h1", "f1", .rook, .white)]
    )
    #expect(diff.added.isEmpty)
    #expect(diff.removed.isEmpty)
  }

  @Test
  func enPassantRemovesThePawnBesideTheTarget() throws {
    let diff = try Self.diff(
      from: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
      to: "4k3/8/3P4/8/8/8/8/4K3 b - - 0 1",
      lastMove: "e5d6"
    )
    #expect(diff.moved == [Self.move("e5", "d6", .pawn, .white)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed == [Self.square("d5")])
  }

  @Test
  func promotionSlidesThePawnAndTurnsItIntoTheNewPiece() throws {
    let diff = try Self.diff(
      from: "1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1",
      to: "1N2k3/8/8/8/8/8/8/4K3 b - - 0 1",
      lastMove: "a7b8n"
    )
    #expect(diff.moved == [Self.move("a7", "b8", .knight, .white)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed == [Self.square("b8")])
  }

  @Test
  func newGameWithoutLastMoveSlidesEachPieceBackToTheNearestSquare() throws {
    let diff = try Self.diff(
      from: "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
      to: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      lastMove: nil
    )
    #expect(
      diff.moved == [Self.move("e4", "e2", .pawn, .white), Self.move("e5", "e7", .pawn, .black)]
    )
    #expect(diff.added.isEmpty)
    #expect(diff.removed.isEmpty)
  }

  @Test
  func appearedPieceSlidesFromTheNearestVacatedSquare() throws {
    let diff = try Self.diff(
      from: "4k3/8/8/8/8/7K/8/N5N1 w - - 0 1",
      to: "4k3/8/8/8/8/7K/8/5N2 w - - 0 1",
      lastMove: nil
    )
    #expect(diff.moved == [Self.move("g1", "f1", .knight, .white)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed == [Self.square("a1")])
  }

  @Test
  func equidistantVacatedSquaresBreakTheTieByLowestSquare() throws {
    let diff = try Self.diff(
      from: "4k3/8/8/8/8/7K/8/3N1N2 w - - 0 1",
      to: "4k3/8/8/8/8/7K/8/4N3 w - - 0 1",
      lastMove: nil
    )
    #expect(diff.moved == [Self.move("d1", "e1", .knight, .white)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed == [Self.square("f1")])
  }

  @Test
  func lastMoveWithTheOtherColourDoesNotSlideThePiece() throws {
    let diff = try Self.diff(
      from: "4k3/4p3/8/8/8/7K/4P3/8 w - - 0 1",
      to: "4k3/8/8/8/4p3/7K/8/8 w - - 0 1",
      lastMove: "e2e4"
    )
    #expect(diff.moved == [Self.move("e7", "e4", .pawn, .black)])
    #expect(diff.added.isEmpty)
    #expect(diff.removed == [Self.square("e2")])
  }

  @Test
  func loadedPositionAddsAndRemovesPiecesWithoutAMatch() throws {
    let diff = try Self.diff(
      from: "4k3/8/8/8/8/8/8/4K2N w - - 0 1",
      to: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1",
      lastMove: nil
    )
    #expect(diff.moved.isEmpty)
    #expect(diff.added == [Self.square("a1"): Piece(type: .rook, color: .white)])
    #expect(diff.removed == [Self.square("h1")])
  }
}
