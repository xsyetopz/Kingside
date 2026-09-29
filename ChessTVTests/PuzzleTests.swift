import XCTest
import ChessCore
@testable import ChessTV

final class PuzzleTests: XCTestCase {
    private func puzzle(_ fen: String, _ moves: String, rating: Int = 1000, id: String = "p") -> Puzzle {
        Puzzle(id: id, fen: fen, moves: moves.split(separator: " ").compactMap { ChessMove(uci: String($0)) },
               rating: rating, themes: [])
    }

    /// Black to move plays b7b6 (intro); white mates with Rd8#.
    private var backRank: Puzzle { puzzle("6k1/1p3ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1", "b7b6 d1d8") }

    /// Intro a7a6, then white Qh5 (listed), black g6, white Qxf7+ ... a three-ply solver line.
    private var twoStep: Puzzle {
        puzzle("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 0 1", "a7a6 d1h5 g8f6 h5f7")
    }

    private func move(_ uci: String) -> ChessMove { ChessMove(uci: uci)! }

    // MARK: Session

    func testIntroThenCorrectMateSolves() throws {
        var session = try PuzzleSession(puzzle: backRank)
        XCTAssertEqual(session.solverColor, .white)
        XCTAssertEqual(session.playIntro(), move("b7b6"))
        XCTAssertEqual(session.phase, .solverToMove)
        XCTAssertEqual(session.submit(move("d1d8")), .solved)
        XCTAssertEqual(session.ratedOutcome, .solved)
    }

    func testCorrectMoveWaitsForOpponentReply() throws {
        var session = try PuzzleSession(puzzle: twoStep)
        session.playIntro()
        XCTAssertEqual(session.submit(move("d1h5")), .correct)
        XCTAssertEqual(session.phase, .opponentToMove)
        XCTAssertEqual(session.submit(move("h5f7")), .ignored)
        XCTAssertEqual(session.playOpponentReply(), move("g8f6"))
        XCTAssertEqual(session.submit(move("h5f7")), .solved)
        XCTAssertEqual(session.ratedOutcome, .solved)
    }

    func testAlternativeCheckmateCountsAsCorrect() throws {
        let twoMates = puzzle("6k1/1p3ppp/8/8/8/8/5PPP/R2R2K1 b - - 0 1", "b7b6 d1d8")
        var session = try PuzzleSession(puzzle: twoMates)
        session.playIntro()
        XCTAssertEqual(session.submit(move("a1a8")), .solved)
        XCTAssertEqual(session.phase, .solved)
    }

    func testWrongMoveFailsAndRetryKeepsFailedOutcome() throws {
        var session = try PuzzleSession(puzzle: backRank)
        session.playIntro()
        let before = session.position
        XCTAssertEqual(session.submit(move("g1f1")), .wrong)
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.position, before)
        XCTAssertEqual(session.ratedOutcome, .failed)
        session.retry()
        XCTAssertEqual(session.submit(move("d1d8")), .solved)
        XCTAssertEqual(session.ratedOutcome, .failed)
    }

    func testHintMakesAttemptUnrated() throws {
        var session = try PuzzleSession(puzzle: backRank)
        session.playIntro()
        XCTAssertEqual(session.hint(), Square(algebraic: "d1"))
        XCTAssertEqual(session.submit(move("d1d8")), .solved)
        XCTAssertEqual(session.ratedOutcome, .unrated)
    }

    func testRevealPlaysRemainingMovesAndFails() throws {
        var session = try PuzzleSession(puzzle: twoStep)
        session.playIntro()
        XCTAssertEqual(session.revealNext(), move("d1h5"))
        XCTAssertEqual(session.ratedOutcome, .failed)
        XCTAssertEqual(session.revealNext(), move("g8f6"))
        XCTAssertEqual(session.revealNext(), move("h5f7"))
        XCTAssertEqual(session.phase, .revealed)
        XCTAssertNil(session.revealNext())
    }

    // MARK: Rating

    func testEloUsesK32ThenK16() {
        XCTAssertEqual(PuzzleRating.change(rating: 800, puzzleRating: 800, solved: true, puzzlesPlayed: 0), 16)
        XCTAssertEqual(PuzzleRating.change(rating: 800, puzzleRating: 800, solved: false, puzzlesPlayed: 49), -16)
        XCTAssertEqual(PuzzleRating.change(rating: 800, puzzleRating: 800, solved: true, puzzlesPlayed: 50), 8)
        // Beating a puzzle 400 points higher: expected score 1/11, gain 32 * 10/11 = 29.
        XCTAssertEqual(PuzzleRating.change(rating: 800, puzzleRating: 1200, solved: true, puzzlesPlayed: 0), 29)
    }

    // MARK: Selection

    func testRatedSelectionStaysInWindowWithoutRepeats() {
        let pool = stride(from: 400, through: 2000, by: 100).map { puzzle("8/8/8/8/8/8/8/8 w - - 0 1", "", rating: $0, id: "r\($0)") }
        var generator = SystemRandomNumberGenerator()
        var seen: Set<String> = []
        for _ in 0..<5 {
            let pick = PuzzleSelector.rated(from: pool, rating: 1000, seen: seen, using: &generator)!
            XCTAssertLessThanOrEqual(abs(pick.rating - 1000), 200)
            XCTAssertFalse(seen.contains(pick.id))
            seen.insert(pick.id)
        }
        // Window exhausted: falls back to the closest unseen puzzle.
        XCTAssertEqual(PuzzleSelector.rated(from: pool, rating: 1000, seen: seen, using: &generator)?.rating, 700)
        XCTAssertNil(PuzzleSelector.rated(from: pool, rating: 1000, seen: Set(pool.map(\.id)), using: &generator))
    }

    func testRushEscalatesFrom400() {
        XCTAssertEqual(PuzzleSelector.rushTargetRating(index: 0), 400)
        XCTAssertLessThan(PuzzleSelector.rushTargetRating(index: 5), PuzzleSelector.rushTargetRating(index: 10))
    }

    func testDailyIsDeterministicPerDay() {
        let pool = (0..<50).map { puzzle("8/8/8/8/8/8/8/8 w - - 0 1", "", rating: 1500, id: "d\($0)") }
        let day = PuzzleDay(year: 2026, month: 9, day: 29)
        XCTAssertEqual(PuzzleSelector.daily(from: pool, day: day), PuzzleSelector.daily(from: pool.reversed(), day: day))
        XCTAssertNotEqual(
            PuzzleSelector.daily(from: pool, day: day),
            PuzzleSelector.daily(from: pool, day: PuzzleDay(year: 2026, month: 9, day: 30))
        )
        XCTAssertEqual(PuzzleDay(year: 1970, month: 1, day: 1).dayNumber, 0)
        XCTAssertEqual(PuzzleDay(year: 2000, month: 3, day: 1).dayNumber, 11_017)
        XCTAssertEqual(day.key, "2026-09-29")
    }

    // MARK: Rush run

    func testRushEndsAtThreeStrikesOrTimeout() {
        var survival = PuzzleRushRun(mode: .survival)
        survival.tick(10_000)
        XCTAssertFalse(survival.isOver)
        survival.recordSolved()
        (0..<3).forEach { _ in survival.recordFailed() }
        XCTAssertTrue(survival.isOver)
        survival.recordSolved()
        XCTAssertEqual(survival.score, 1)

        var timed = PuzzleRushRun(mode: .threeMinutes)
        timed.tick(179)
        XCTAssertFalse(timed.isOver)
        timed.tick(5)
        XCTAssertEqual(timed.remaining, 0)
        XCTAssertTrue(timed.isOver)
    }

    // MARK: Progress store

    @MainActor
    func testProgressStoreRoundTrip() {
        let suite = "ChessTVTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PuzzleProgressStore(defaults: defaults)
        XCTAssertEqual(first.progress.rating, 800)
        XCTAssertEqual(first.recordRated(puzzleRating: 800, solved: true), 16)
        first.markSeen("abc")
        XCTAssertTrue(first.recordRush(mode: .fiveMinutes, score: 12))
        XCTAssertFalse(first.recordRush(mode: .fiveMinutes, score: 7))
        first.markDailySolved(PuzzleDay(year: 2026, month: 9, day: 29))

        let second = PuzzleProgressStore(defaults: defaults)
        XCTAssertEqual(second.progress.rating, 816)
        XCTAssertEqual(second.progress.ratedPlayed, 1)
        XCTAssertEqual(second.progress.streak, 1)
        XCTAssertEqual(second.progress.seenIDs, ["abc"])
        XCTAssertEqual(second.rushBest(for: .fiveMinutes), 12)
        XCTAssertTrue(second.isDailySolved(PuzzleDay(year: 2026, month: 9, day: 29)))
    }

    func testBundledPuzzlesDecode() {
        let puzzles = PuzzleLibrary.load(from: Bundle(for: PuzzleProgressStore.self))
        XCTAssertGreaterThan(puzzles.count, 1000)
        XCTAssertTrue(puzzles.allSatisfy { $0.moves.count >= 2 && $0.initialPosition != nil })
    }
}
