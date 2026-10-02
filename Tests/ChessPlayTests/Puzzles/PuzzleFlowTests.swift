import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

/// The rated, Puzzle Rush, and Daily Puzzle sessions on top of a `PuzzleBoardSession`, driven by a
/// test clock so the board's and the run's delays pass on demand.
@MainActor
@Suite(.timeLimit(.minutes(1)))
final class PuzzleFlowTests {
  private let suiteName = "PuzzleFlowTests.\(UUID().uuidString)"
  private let clock = TestClock()
  private let catalog: ContentCatalog
  private let progress: PuzzleProgressStore

  init() throws {
    catalog = try Shared.catalog
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    progress = PuzzleProgressStore(defaults: defaults, rating: catalog.tuning.puzzleRating)
  }

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
  }

  private func makeBoard() -> PuzzleBoardSession {
    PuzzleBoardSession(catalog: catalog, clock: clock)
  }

  /// Moves the clock in small steps until `condition` holds.
  private func advance(until condition: () -> Bool) async {
    while !condition() {
      clock.advance(by: .milliseconds(100))
      await Task.yield()
    }
  }

  /// Plays the puzzle's listed solver moves through the board's input.
  private func solve(_ board: PuzzleBoardSession) async throws {
    let puzzle = try #require(board.session?.puzzle)
    for index in stride(from: 1, to: puzzle.moves.count, by: 2) {
      await advance { board.phase != .intro && board.phase != .opponentToMove }
      guard board.phase == .solverToMove else { return }
      let move = puzzle.moves[index]
      board.apply(.select(move.from))
      board.apply(.select(move.to))
      if let promotion = move.promotion { board.apply(.promote(promotion)) }
    }
  }

  /// Lets the intro play, then walks through the solution, which counts as a failed attempt.
  private func fail(_ board: PuzzleBoardSession) async {
    await advance { board.phase == .solverToMove }
    board.showSolution()
    await advance { board.session?.ratedOutcome != nil }
  }

  // MARK: Rated

  @Test
  func ratedStartLoadsAnUnseenPuzzleNearTheRating() throws {
    let rated = RatedPuzzleSession(catalog: catalog, progress: progress, board: makeBoard())
    rated.start()
    let puzzle = try #require(rated.puzzle)
    #expect(
      abs(puzzle.rating - progress.progress.rating) <= catalog.tuning.puzzleSelection.ratedWindow
    )
    #expect(progress.progress.seenIDs == [puzzle.id])
    #expect(rated.board.session?.puzzle.id == puzzle.id)

    rated.start()
    #expect(rated.puzzle == puzzle)
  }

  @Test
  func solvingARatedPuzzleRaisesTheRatingAndStreak() async throws {
    let rated = RatedPuzzleSession(catalog: catalog, progress: progress, board: makeBoard())
    rated.start()
    let before = progress.progress.rating
    try await solve(rated.board)
    #expect(rated.outcome == .solved)
    let change = try #require(rated.ratingChange)
    #expect(change > 0)
    #expect(progress.progress.rating == before + change)
    #expect(progress.progress.streak == 1)
    #expect(progress.progress.ratedPlayed == 1)
  }

  @Test
  func aRevealedSolutionLowersTheRatingAndResetsTheStreak() async throws {
    progress.recordStreak(solved: true)
    let rated = RatedPuzzleSession(catalog: catalog, progress: progress, board: makeBoard())
    rated.start()
    await fail(rated.board)
    #expect(rated.outcome == .failed)
    #expect(try #require(rated.ratingChange) < 0)
    #expect(progress.progress.streak == 0)
  }

  @Test
  func aHintMakesTheAttemptUnrated() async throws {
    let rated = RatedPuzzleSession(catalog: catalog, progress: progress, board: makeBoard())
    rated.start()
    await advance { rated.board.phase == .solverToMove }
    rated.board.apply(.requestHint)
    rated.board.showSolution()
    await advance { rated.outcome != nil }
    #expect(rated.outcome == .unrated)
    #expect(rated.ratingChange == nil)
    #expect(progress.progress.rating == catalog.tuning.puzzleRating.initial)
    #expect(progress.progress.ratedPlayed == 0)
  }

  @Test
  func nextLoadsAnotherPuzzleAndClearsTheResult() async throws {
    let rated = RatedPuzzleSession(catalog: catalog, progress: progress, board: makeBoard())
    rated.start()
    let first = try #require(rated.puzzle)
    await fail(rated.board)
    rated.next()
    let second = try #require(rated.puzzle)
    #expect(second != first)
    #expect(rated.outcome == nil && rated.ratingChange == nil)
    #expect(rated.board.session?.puzzle.id == second.id)
    #expect(progress.progress.seenIDs == [first.id, second.id])
  }

  @Test
  func seenPuzzlesStartOverWhenAllAreSeen() throws {
    catalog.puzzles.forEach { progress.markSeen($0.id) }
    let rated = RatedPuzzleSession(catalog: catalog, progress: progress, board: makeBoard())
    rated.start()
    #expect(rated.puzzle != nil)
    #expect(progress.progress.seenIDs.count == 1)
  }

  // MARK: Daily

  private let day = PuzzleDay(year: 2026, month: 9, day: 29)

  @Test
  func dailyLoadsTheDaysPuzzleAndMarksItSolved() async throws {
    let daily = DailyPuzzleSession(
      day: day,
      catalog: catalog,
      progress: progress,
      board: makeBoard()
    )
    daily.start()
    let expected = try #require(
      PuzzleSelector(tuning: catalog.tuning.puzzleSelection).daily(from: catalog.puzzles, day: day)
    )
    #expect(daily.puzzle == expected)
    #expect(daily.board.session?.puzzle.id == expected.id)
    #expect(!daily.isSolved)

    try await solve(daily.board)
    daily.boardPhaseChanged()
    #expect(daily.isSolved)
    #expect(progress.isDailySolved(day))
  }

  @Test
  func dailyIsNotSolvedByRevealingTheSolutionAndStartsOver() async throws {
    let daily = DailyPuzzleSession(
      day: day,
      catalog: catalog,
      progress: progress,
      board: makeBoard()
    )
    daily.start()
    await fail(daily.board)
    await advance { daily.board.phase == .revealed }
    daily.boardPhaseChanged()
    #expect(!daily.isSolved)

    daily.startOver()
    #expect(daily.board.phase == .intro)
    #expect(daily.board.session?.puzzle == daily.puzzle)
  }

  // MARK: Rush

  private func makeRush(_ mode: PuzzleRushMode) -> PuzzleRushSession {
    PuzzleRushSession(
      mode: mode,
      catalog: catalog,
      progress: progress,
      board: makeBoard(),
      clock: clock
    )
  }

  @Test
  func rushStartsWithTheEasiestPuzzles() throws {
    let rush = makeRush(.survival)
    rush.start()
    let puzzle = try #require(rush.board.session?.puzzle)
    let selection = catalog.tuning.puzzleSelection
    #expect(abs(puzzle.rating - selection.rushStartRating) <= selection.rushWindow)
    #expect(rush.run.score == 0 && rush.run.strikes == 0 && rush.result == nil)
  }

  @Test
  func aSolvedPuzzleScoresAndTheNextOneLoadsAfterTheDelay() async throws {
    let rush = makeRush(.survival)
    rush.start()
    let first = try #require(rush.board.session?.puzzle)
    try await solve(rush.board)
    #expect(rush.run.score == 1)
    #expect(rush.board.session?.puzzle == first)

    await advance { rush.board.session?.puzzle != first }
    #expect(rush.board.phase == .intro)
    #expect(rush.result == nil)
  }

  @Test
  func strikesEndTheRunAndTheBestScoreIsSaved() async throws {
    let rush = makeRush(.survival)
    rush.start()
    try await solve(rush.board)
    await advance { rush.run.puzzlesPlayed == 1 && rush.board.phase == .intro }
    for _ in 0..<catalog.tuning.puzzleRush.maxStrikes {
      await fail(rush.board)
      await advance { rush.result != nil || rush.board.phase == .intro }
    }
    let result = try #require(rush.result)
    #expect(result == PuzzleRushSession.Result(score: 1, isNewBest: true, best: 1))
    #expect(progress.rushBest(for: .survival) == 1)
    #expect(rush.run.isOver)

    rush.start()
    #expect(rush.result == nil && rush.run.score == 0)
  }

  @Test
  func aLowerScoreIsNotANewBest() throws {
    progress.recordRush(mode: .survival, score: 5)
    let rush = makeRush(.survival)
    rush.start()
    rush.end()
    #expect(
      rush.result == PuzzleRushSession.Result(score: 0, isNewBest: false, best: 5)
    )
  }

  @Test
  func aTimedRunEndsWhenTheClockRunsOut() async throws {
    let rush = makeRush(.threeMinutes)
    rush.start()
    let limit = try #require(
      PuzzleRushMode.threeMinutes.timeLimit(tuning: catalog.tuning.puzzleRush)
    )
    // The clock holds while the opponent makes the first move.
    clock.advance(by: .milliseconds(50))
    await Task.yield()
    #expect(rush.run.remaining == limit)

    await advance { rush.board.phase == .solverToMove }
    let held = try #require(rush.run.remaining)
    await advance { rush.run.remaining != held }
    #expect(try #require(rush.run.remaining) < held)

    clock.advance(by: .seconds(limit))
    // The clock task may not be asleep yet when the clock jumps, so keep time moving.
    await advance { rush.result != nil }
    #expect(rush.run.remaining == 0)
    #expect(rush.result?.score == 0)
  }

  @Test
  func stoppingAFinishedOrLeftRunSavesNothingFurther() async throws {
    let rush = makeRush(.threeMinutes)
    rush.start()
    rush.stop()
    clock.advance(by: .seconds(1000))
    await Task.yield()
    #expect(rush.result == nil)
    #expect(rush.run.remaining == catalog.tuning.puzzleRush.timeLimits["threeMinutes"])
  }
}
