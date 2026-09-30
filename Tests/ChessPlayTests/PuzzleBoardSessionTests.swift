import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@MainActor
@Suite(.timeLimit(.minutes(1)))
final class PuzzleBoardSessionTests {
  private let sink = RecordingFeedbackSink()
  private let clock = TestClock()
  private var outcomes: [PuzzleSession.RatedOutcome] = []

  private func makeSession() throws -> PuzzleBoardSession {
    let session = PuzzleBoardSession(catalog: try Shared.catalog, feedback: sink, clock: clock)
    session.onOutcome = { [weak self] in self?.outcomes.append($0) }
    return session
  }

  /// `Puzzle` has no public memberwise init; build one from its `puzzles.json` shape.
  private func puzzle(_ fen: String, _ moves: String) throws -> Puzzle {
    let entry: [String: Any] = [
      "id": "p", "fen": fen, "moves": moves, "rating": 1000, "themes": "",
    ]
    return try JSONDecoder().decode(
      Puzzle.self,
      from: JSONSerialization.data(withJSONObject: entry)
    )
  }

  /// Black plays b7b6 (intro); white mates with Rd8#.
  private func backRank() throws -> Puzzle {
    try puzzle("6k1/1p3ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1", "b7b6 d1d8")
  }

  /// Intro a7a6, then Qh5 (listed), Nf6, Qxf7.
  private func twoStep() throws -> Puzzle {
    try puzzle(
      "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 0 1",
      "a7a6 d1h5 g8f6 h5f7"
    )
  }

  /// Black plays Kg8 (intro); white promotes with a7a8q.
  private func promotion() throws -> Puzzle {
    try puzzle("7k/P7/8/8/8/8/8/K7 b - - 0 1", "h8g8 a7a8q")
  }

  private func square(_ name: String) throws -> Square { try #require(Square(algebraic: name)) }

  private func play(_ uci: String, in session: PuzzleBoardSession) throws {
    let move = try #require(ChessMove(uci: uci))
    session.apply(.select(move.from))
    session.apply(.select(move.to))
  }

  /// Loads `puzzle` and lets the intro move play.
  private func loadAndPlayIntro(_ puzzle: Puzzle, in session: PuzzleBoardSession) async throws {
    session.load(puzzle)
    await clock.waitForSleeper()
    clock.advance(by: try Shared.catalog.tuning.puzzleBoard.introDelay)
    await sink.wait { $0.count == 1 }
  }

  private var replyDelay: Duration {
    get throws { try Shared.catalog.tuning.puzzleBoard.replyDelay }
  }

  @Test
  func introMoveAutoPlaysAfterTheDelay() async throws {
    let session = try makeSession()
    session.load(try backRank())
    #expect(session.phase == .intro)
    #expect(!session.snapshot.isInputEnabled)
    #expect(session.snapshot.pieces[try square("b7")] != nil)

    await clock.waitForSleeper()
    clock.advance(by: try Shared.catalog.tuning.puzzleBoard.introDelay)
    await sink.wait { !$0.isEmpty }

    #expect(session.phase == .solverToMove)
    #expect(sink.events == [.moved(.move)])
    let snapshot = session.snapshot
    #expect(snapshot.pieces[try square("b6")] == Piece(type: .pawn, color: .black))
    #expect(snapshot.pieces[try square("b7")] == nil)
    #expect(snapshot.lastMove == ChessMove(uci: "b7b6"))
    #expect(snapshot.orientation == .white)
    #expect(snapshot.isInputEnabled)
    #expect(snapshot.badge == nil)
    #expect(outcomes.isEmpty)
  }

  @Test
  func correctMoveIsBadgedThenOpponentRepliesAndSolvingReportsOnce() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try twoStep(), in: session)

    try play("d1h5", in: session)
    #expect(session.phase == .opponentToMove)
    #expect(session.snapshot.badge == SquareBadge(square: try square("h5"), kind: .correct))
    #expect(!session.snapshot.isInputEnabled)
    #expect(sink.events.last == .puzzleCorrect)

    await clock.waitForSleeper()
    clock.advance(by: try replyDelay)
    await sink.wait { $0.count == 3 }
    #expect(sink.events.last == .moved(.move))
    #expect(session.phase == .solverToMove)
    #expect(session.snapshot.badge == nil)
    #expect(session.snapshot.lastMove == ChessMove(uci: "g8f6"))
    #expect(outcomes.isEmpty)

    try play("h5f7", in: session)
    #expect(session.phase == .solved)
    #expect(session.snapshot.badge == SquareBadge(square: try square("f7"), kind: .correct))
    #expect(outcomes == [.solved])
    #expect(!session.canShowSolution && !session.canRetry && !session.canHint)
  }

  @Test
  func wrongMoveFailsWithIncorrectBadgeAndReportsOnce() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try backRank(), in: session)

    try play("g1f1", in: session)
    #expect(session.phase == .failed)
    #expect(session.canRetry && session.canShowSolution)
    let snapshot = session.snapshot
    #expect(snapshot.badge == SquareBadge(square: try square("f1"), kind: .incorrect))
    #expect(snapshot.pieces[try square("f1")] == Piece(type: .king, color: .white))
    #expect(!snapshot.isInputEnabled)
    #expect(sink.events.last == .puzzleWrong)
    #expect(outcomes == [.failed])

    try play("d1d8", in: session)
    #expect(outcomes == [.failed])
  }

  @Test
  func retryRestoresThePositionAndKeepsTheFailedOutcome() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try backRank(), in: session)
    let before = session.snapshot.pieces

    try play("g1f1", in: session)
    session.retry()

    #expect(session.phase == .solverToMove)
    #expect(session.snapshot.pieces == before)
    #expect(session.snapshot.badge == nil)
    #expect(session.snapshot.lastMove == ChessMove(uci: "b7b6"))
    #expect(session.snapshot.isInputEnabled)

    try play("d1d8", in: session)
    #expect(session.phase == .solved)
    #expect(outcomes == [.failed])
  }

  @Test
  func illegalTargetPlaysTheIllegalMoveFeedback() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try backRank(), in: session)

    session.apply(.select(try square("d1")))
    session.apply(.select(try square("a5")))

    #expect(sink.events.last == .illegalMove)
    #expect(session.snapshot.selectedSquare == nil)
    #expect(session.phase == .solverToMove)
  }

  @Test
  func hintFocusesAndPicksUpThePieceAndMakesTheOutcomeUnrated() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try backRank(), in: session)
    #expect(session.canHint)

    session.apply(.requestHint)

    let d1 = try square("d1")
    #expect(session.snapshot.focusedSquare == d1)
    #expect(session.snapshot.selectedSquare == d1)
    #expect(session.snapshot.legalTargets.contains(try square("d8")))
    try play("d1d8", in: session)
    #expect(outcomes == [.unrated])
  }

  @Test
  func promotionAsksForThePieceThenSolves() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try promotion(), in: session)

    session.apply(.select(try square("a7")))
    session.apply(.select(try square("a8")))
    let pending = try #require(session.snapshot.pendingPromotion)
    #expect(pending.color == .white)
    #expect(Set(pending.choices) == [.queen, .rook, .bishop, .knight])
    #expect(!session.snapshot.isInputEnabled)

    session.apply(.cancel)
    #expect(session.snapshot.pendingPromotion == nil)
    session.apply(.select(try square("a7")))
    session.apply(.select(try square("a8")))
    session.apply(.promote(.queen))

    #expect(session.phase == .solved)
    #expect(session.snapshot.pieces[try square("a8")] == Piece(type: .queen, color: .white))
    #expect(outcomes == [.solved])
  }

  @Test
  func promotingToTheWrongPieceFails() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try promotion(), in: session)

    session.apply(.select(try square("a7")))
    session.apply(.select(try square("a8")))
    session.apply(.promote(.knight))

    #expect(session.phase == .failed)
    #expect(outcomes == [.failed])
  }

  @Test
  func showSolutionPlaysTheRemainingMovesStepByStep() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try twoStep(), in: session)
    let step = try Shared.catalog.tuning.puzzleBoard.solutionStepDelay

    session.showSolution()
    #expect(outcomes.isEmpty)
    for (index, expected) in ["d1h5", "g8f6", "h5f7"].enumerated() {
      await clock.waitForSleeper()
      clock.advance(by: step)
      await sink.wait { $0.count == index + 2 }
      #expect(session.snapshot.lastMove == ChessMove(uci: expected))
    }

    #expect(session.phase == .revealed)
    #expect(session.snapshot.pieces[try square("f7")] == Piece(type: .queen, color: .white))
    #expect(outcomes == [.failed])
    #expect(!session.snapshot.isInputEnabled)
  }

  @Test
  func flipBoardTogglesTheOrientationAndGameIntentsAreIgnored() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try backRank(), in: session)
    let before = session.snapshot

    session.apply(.resign)
    session.apply(.takeback)
    #expect(session.snapshot == before)

    session.apply(.flipBoard)
    #expect(session.snapshot.orientation == .black)
    session.apply(.flipBoard)
    #expect(session.snapshot.orientation == .white)
  }

  @Test
  func loadingAgainResetsTheAttempt() async throws {
    let session = try makeSession()
    try await loadAndPlayIntro(try backRank(), in: session)
    try play("g1f1", in: session)
    #expect(outcomes == [.failed])

    session.load(try backRank())
    #expect(session.phase == .intro)
    #expect(session.snapshot.badge == nil)
    await clock.waitForSleeper()
    clock.advance(by: try Shared.catalog.tuning.puzzleBoard.introDelay)
    await sink.wait { $0.count == 3 }
    try play("d1d8", in: session)
    #expect(outcomes == [.failed, .solved])
  }
}
