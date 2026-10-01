import ChessCore
import Testing

@testable import ChessPlay

@Suite
struct MoveInputTests {
  /// White pawn on a7 promotes on a8; the kings are out of the way.
  private let promotionFEN = "7k/P7/8/8/8/8/8/K7 w - - 0 1"

  private func square(_ name: String) throws -> Square { try #require(Square(algebraic: name)) }

  private func move(_ uci: String) throws -> ChessMove { try #require(ChessMove(uci: uci)) }

  /// Selects a7, then a8, in the promotion position.
  private func pushPawnToEighth(
    _ input: inout MoveInput,
    autoQueen: Bool
  ) throws -> MoveInput.Outcome {
    let position = try ChessPosition(fen: promotionFEN)
    _ = input.select(try square("a7"), in: position, movableColor: .white, autoQueen: autoQueen)
    return input.select(try square("a8"), in: position, movableColor: .white, autoQueen: autoQueen)
  }

  @Test
  func promotionOpensThePickerAndDisablesInput() throws {
    var input = MoveInput()
    #expect(try pushPawnToEighth(&input, autoQueen: false) == .none)
    let snapshot = input.snapshot(of: try ChessPosition(fen: promotionFEN), canMove: true)
    let pending = try #require(snapshot.pendingPromotion)
    #expect(pending.from == (try square("a7")))
    #expect(pending.to == (try square("a8")))
    #expect(pending.color == .white)
    #expect(pending.choices == [.queen, .rook, .bishop, .knight])
    #expect(!snapshot.isInputEnabled)
  }

  @Test
  func autoQueenPlaysTheQueenWithoutThePicker() throws {
    var input = MoveInput()
    #expect(try pushPawnToEighth(&input, autoQueen: true) == .play(try move("a7a8q")))
    #expect(!input.isChoosingPromotion)
  }

  @Test
  func promoteReturnsTheChosenMoveOnce() throws {
    var input = MoveInput()
    _ = try pushPawnToEighth(&input, autoQueen: false)
    #expect(input.promote(.knight) == (try move("a7a8n")))
    #expect(input.promote(.knight) == nil)
  }

  @Test
  func cancelClosesThePickerAndDropsTheSelection() throws {
    var input = MoveInput()
    _ = try pushPawnToEighth(&input, autoQueen: false)
    input.cancel()
    #expect(!input.hasCancellableSelection)
    #expect(input.snapshot(of: try ChessPosition(fen: promotionFEN), canMove: true).isInputEnabled)
  }

  @Test
  func completeRecordsTheMoveAndClosesThePicker() throws {
    var input = MoveInput()
    _ = try pushPawnToEighth(&input, autoQueen: false)
    input.complete(try move("a7a8q"))
    #expect(!input.hasCancellableSelection)
    #expect(input.lastMove == (try move("a7a8q")))
    #expect(input.focusedSquare == (try square("a8")))
  }

  @Test
  func anUnreachableSquareIsAnIllegalTarget() throws {
    var input = MoveInput()
    let position = ChessPosition.initial
    _ = input.select(try square("e2"), in: position, movableColor: .white, autoQueen: false)
    let outcome = input.select(
      try square("e5"),
      in: position,
      movableColor: .white,
      autoQueen: false
    )
    #expect(outcome == .illegalTarget)
    #expect(!input.hasCancellableSelection)
  }

  @Test
  func snapshotMarksTheCheckedKing() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/8/4R1K1 b - - 0 1")
    let snapshot = MoveInput().snapshot(of: position, canMove: false)
    #expect(snapshot.checkSquare == (try square("e8")))
  }
}
