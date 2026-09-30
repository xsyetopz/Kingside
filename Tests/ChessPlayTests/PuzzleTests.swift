import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@Suite struct PuzzleTests {
    /// `Puzzle` has no public memberwise init; build one from its `puzzles.json` shape.
    private func puzzle(_ fen: String, _ moves: String, rating: Int = 1000, id: String = "p") throws -> Puzzle {
        let entry: [String: Any] = ["id": id, "fen": fen, "moves": moves, "rating": rating, "themes": ""]
        return try JSONDecoder().decode(Puzzle.self, from: JSONSerialization.data(withJSONObject: entry))
    }

    /// Black to move plays b7b6 (intro); white mates with Rd8#.
    private func backRank() throws -> Puzzle { try puzzle("6k1/1p3ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1", "b7b6 d1d8") }

    /// Intro a7a6, then white Qh5 (listed), black Nf6, white Qxf7: a three-ply solver line.
    private func twoStep() throws -> Puzzle {
        try puzzle("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 0 1", "a7a6 d1h5 g8f6 h5f7")
    }

    private func move(_ uci: String) throws -> ChessMove { try #require(ChessMove(uci: uci)) }

    // MARK: Session

    @Test func introThenCorrectMateSolves() throws {
        let session = try PuzzleSession(puzzle: backRank())
        #expect(session.solverColor == .white)
        #expect(session.playIntro() == (try move("b7b6")))
        #expect(session.phase == .solverToMove)
        #expect(session.submit(try move("d1d8")) == .solved)
        #expect(session.ratedOutcome == .solved)
    }

    @Test func correctMoveWaitsForOpponentReply() throws {
        let session = try PuzzleSession(puzzle: twoStep())
        session.playIntro()
        #expect(session.submit(try move("d1h5")) == .correct)
        #expect(session.phase == .opponentToMove)
        #expect(session.submit(try move("h5f7")) == .ignored)
        #expect(session.playOpponentReply() == (try move("g8f6")))
        #expect(session.submit(try move("h5f7")) == .solved)
        #expect(session.ratedOutcome == .solved)
    }

    @Test func alternativeCheckmateCountsAsCorrect() throws {
        let twoMates = try puzzle("6k1/1p3ppp/8/8/8/8/5PPP/R2R2K1 b - - 0 1", "b7b6 d1d8")
        let session = try PuzzleSession(puzzle: twoMates)
        session.playIntro()
        #expect(session.submit(try move("a1a8")) == .solved)
        #expect(session.phase == .solved)
    }

    @Test func wrongMoveFailsAndRetryKeepsFailedOutcome() throws {
        let session = try PuzzleSession(puzzle: backRank())
        session.playIntro()
        let before = session.position
        #expect(session.submit(try move("g1f1")) == .wrong)
        #expect(session.phase == .failed)
        #expect(session.position == before)
        #expect(session.ratedOutcome == .failed)
        session.retry()
        #expect(session.submit(try move("d1d8")) == .solved)
        #expect(session.ratedOutcome == .failed)
    }

    @Test func hintMakesAttemptUnrated() throws {
        let session = try PuzzleSession(puzzle: backRank())
        session.playIntro()
        #expect(session.hint() == Square(algebraic: "d1"))
        #expect(session.submit(try move("d1d8")) == .solved)
        #expect(session.ratedOutcome == .unrated)
    }

    @Test func revealPlaysRemainingMovesAndFails() throws {
        let session = try PuzzleSession(puzzle: twoStep())
        session.playIntro()
        #expect(session.revealNext() == (try move("d1h5")))
        #expect(session.ratedOutcome == .failed)
        #expect(session.revealNext() == (try move("g8f6")))
        #expect(session.revealNext() == (try move("h5f7")))
        #expect(session.phase == .revealed)
        #expect(session.revealNext() == nil)
    }

    // MARK: Rating

    @Test func eloUsesProvisionalThenEstablishedKFactor() throws {
        let tuning = try Shared.catalog.tuning.puzzleRating
        // The expected numbers below assume these tuning values.
        try #require(tuning.provisionalGames == 50)
        try #require(tuning.provisionalKFactor == 32)
        try #require(tuning.establishedKFactor == 16)

        #expect(tuning.change(rating: 800, puzzleRating: 800, solved: true, puzzlesPlayed: 0) == 16)
        #expect(tuning.change(rating: 800, puzzleRating: 800, solved: false, puzzlesPlayed: 49) == -16)
        #expect(tuning.change(rating: 800, puzzleRating: 800, solved: true, puzzlesPlayed: 50) == 8)
        // Beating a puzzle 400 points higher: expected score 1/11, gain 32 * 10/11 = 29.
        #expect(tuning.change(rating: 800, puzzleRating: 1200, solved: true, puzzlesPlayed: 0) == 29)
    }

    // MARK: Selection

    @Test func ratedSelectionStaysInWindowWithoutRepeats() throws {
        let selector = PuzzleSelector(tuning: try Shared.catalog.tuning.puzzleSelection)
        try #require(selector.tuning.ratedWindow == 200)
        let pool = try stride(from: 400, through: 2000, by: 100).map {
            try puzzle("8/8/8/8/8/8/8/8 w - - 0 1", "", rating: $0, id: "r\($0)")
        }
        var generator = SystemRandomNumberGenerator()
        var seen: Set<String> = []
        for _ in 0..<5 {
            let pick = try #require(selector.rated(from: pool, rating: 1000, seen: seen, using: &generator))
            #expect(abs(pick.rating - 1000) <= 200)
            #expect(!seen.contains(pick.id))
            seen.insert(pick.id)
        }
        // Window exhausted: falls back to the closest unseen puzzle.
        #expect(selector.rated(from: pool, rating: 1000, seen: seen, using: &generator)?.rating == 700)
        #expect(selector.rated(from: pool, rating: 1000, seen: Set(pool.map(\.id)), using: &generator) == nil)
    }

    @Test func rushEscalatesFromStartRating() throws {
        let selector = PuzzleSelector(tuning: try Shared.catalog.tuning.puzzleSelection)
        #expect(selector.tuning.rushStartRating == 400)
        #expect(selector.rushTargetRating(index: 0) == 400)
        #expect(selector.rushTargetRating(index: 5) < selector.rushTargetRating(index: 10))
    }

    @Test func dailyIsDeterministicPerDay() throws {
        let selector = PuzzleSelector(tuning: try Shared.catalog.tuning.puzzleSelection)
        try #require(selector.dailyRatings.contains(1500))
        let pool = try (0..<50).map { try puzzle("8/8/8/8/8/8/8/8 w - - 0 1", "", rating: 1500, id: "d\($0)") }
        let day = PuzzleDay(year: 2026, month: 9, day: 29)
        let today = selector.daily(from: pool, day: day)
        #expect(today != nil)
        #expect(today == selector.daily(from: pool.reversed(), day: day))
        #expect(today != selector.daily(from: pool, day: PuzzleDay(year: 2026, month: 9, day: 30)))
        #expect(PuzzleDay(year: 1970, month: 1, day: 1).dayNumber == 0)
        #expect(PuzzleDay(year: 2000, month: 3, day: 1).dayNumber == 11_017)
        #expect(day.key == "2026-09-29")
    }

    // MARK: Rush run

    @Test func rushEndsAtThreeStrikesOrTimeout() throws {
        let tuning = try Shared.catalog.tuning.puzzleRush
        try #require(tuning.maxStrikes == 3)
        try #require(PuzzleRushMode.threeMinutes.timeLimit(tuning: tuning) == 180)

        var survival = PuzzleRushRun(mode: .survival, tuning: tuning)
        survival.tick(10_000)
        #expect(!survival.isOver)
        survival.recordSolved()
        (0..<3).forEach { _ in survival.recordFailed() }
        #expect(survival.isOver)
        survival.recordSolved()
        #expect(survival.score == 1)

        var timed = PuzzleRushRun(mode: .threeMinutes, tuning: tuning)
        timed.tick(179)
        #expect(!timed.isOver)
        timed.tick(5)
        #expect(timed.remaining == 0)
        #expect(timed.isOver)
    }

    // MARK: Progress store

    @MainActor
    @Test func progressStoreRoundTrip() throws {
        let tuning = try Shared.catalog.tuning.puzzleRating
        try withTemporaryDefaults { defaults in
            let first = PuzzleProgressStore(defaults: defaults, rating: tuning)
            #expect(first.progress.rating == tuning.initial)
            #expect(tuning.initial == 800)
            #expect(first.recordRated(puzzleRating: 800, solved: true) == 16)
            first.markSeen("abc")
            #expect(first.recordRush(mode: .fiveMinutes, score: 12))
            #expect(!first.recordRush(mode: .fiveMinutes, score: 7))
            first.markDailySolved(PuzzleDay(year: 2026, month: 9, day: 29))

            let second = PuzzleProgressStore(defaults: defaults, rating: tuning)
            #expect(second.progress.rating == 816)
            #expect(second.progress.ratedPlayed == 1)
            #expect(second.progress.streak == 1)
            #expect(second.progress.seenIDs == ["abc"])
            #expect(second.rushBest(for: .fiveMinutes) == 12)
            #expect(second.isDailySolved(PuzzleDay(year: 2026, month: 9, day: 29)))
        }
    }

    @MainActor
    @Test func ratingIsClampedAtMinimum() throws {
        let tuning = try Shared.catalog.tuning.puzzleRating
        try withTemporaryDefaults { defaults in
            let start = PuzzleProgress(rating: tuning.minimum + 5)
            defaults.set(try JSONEncoder().encode(start), forKey: PuzzleProgressStore.defaultsKey)
            let store = PuzzleProgressStore(defaults: defaults, rating: tuning)
            #expect(store.progress.rating == tuning.minimum + 5)

            // An even puzzle lost costs half the K-factor, more than the 5 points above the floor.
            let delta = store.recordRated(puzzleRating: tuning.minimum + 5, solved: false)
            #expect(delta == -Int(tuning.provisionalKFactor / 2))
            #expect(store.progress.rating == tuning.minimum)

            store.recordRated(puzzleRating: tuning.minimum, solved: false)
            #expect(store.progress.rating == tuning.minimum)
            #expect(store.progress.ratedPlayed == 2)
            #expect(store.progress.streak == 0)
        }
    }

    /// JSON the app wrote under `Kingside.puzzleProgress.v1` before `ChessPlay` existed.
    @MainActor
    @Test func legacyProgressStillDecodes() throws {
        let tuning = try Shared.catalog.tuning.puzzleRating
        let legacy = """
            {"rating":1234,"ratedPlayed":57,"streak":3,"bestStreak":9,\
            "rushBest":{"threeMinutes":14,"survival":22},"seenIDs":["00sHx","01Qwe"],\
            "dailySolved":["2026-09-28"]}
            """
        try withTemporaryDefaults { defaults in
            defaults.set(Data(legacy.utf8), forKey: "Kingside.puzzleProgress.v1")
            let store = PuzzleProgressStore(defaults: defaults, rating: tuning)
            #expect(store.progress.rating == 1234)
            #expect(store.progress.ratedPlayed == 57)
            #expect(store.progress.streak == 3)
            #expect(store.progress.bestStreak == 9)
            #expect(store.rushBest(for: .threeMinutes) == 14)
            #expect(store.rushBest(for: .survival) == 22)
            #expect(store.rushBest(for: .fiveMinutes) == 0)
            #expect(store.progress.seenIDs == ["00sHx", "01Qwe"])
            #expect(store.isDailySolved(PuzzleDay(year: 2026, month: 9, day: 28)))
        }
    }

    @Test func bundledPuzzlesAreValid() throws {
        let puzzles = try Shared.catalog.puzzles
        #expect(puzzles.count > 1000)
        let invalid = puzzles.filter { puzzle in
            puzzle.moves.count < 2 || (try? puzzle.initialPosition()) == nil
        }.map(\.id)
        #expect(invalid.isEmpty, "Invalid puzzles: \(invalid)")
    }
}
