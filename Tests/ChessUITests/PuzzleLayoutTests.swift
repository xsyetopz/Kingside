import ChessCore
import ChessPlay
import Foundation
import Testing
@testable import ChessUI

struct PuzzleLayoutTests {
    @Test func statusNamesTheSolverToMoveAndReusesTheOpponentLine() {
        #expect(PuzzleLayout.statusKey(phase: .solverToMove, solverColor: .white) == "game.turn.white")
        #expect(PuzzleLayout.statusKey(phase: .solverToMove, solverColor: .black) == "game.turn.black")
        #expect(PuzzleLayout.statusKey(phase: .intro, solverColor: .black) == "game.turn.opponent")
        #expect(PuzzleLayout.statusKey(phase: .opponentToMove, solverColor: .white) == "game.turn.opponent")
    }

    @Test func statusHasALinePerEndPhase() {
        #expect(PuzzleLayout.statusKey(phase: .solved, solverColor: .white) == "puzzles.status.solved")
        #expect(PuzzleLayout.statusKey(phase: .failed, solverColor: .white) == "puzzles.status.failed")
        #expect(PuzzleLayout.statusKey(phase: .revealing, solverColor: .white) == "puzzles.status.revealing")
        #expect(PuzzleLayout.statusKey(phase: .revealed, solverColor: .white) == "puzzles.status.revealed")
    }

    @Test func ratingChangeShowsItsSign() {
        #expect(PuzzleLayout.ratingChangeText(12) == "+12")
        #expect(PuzzleLayout.ratingChangeText(-8) == "-8")
        #expect(PuzzleLayout.ratingChangeText(0) == "0")
    }

    @Test func everyRushModeHasItsOwnSymbol() {
        let symbols = PuzzleRushMode.allCases.map(PuzzleLayout.symbol(for:))
        #expect(Set(symbols).count == PuzzleRushMode.allCases.count)
        #expect(!symbols.contains(""))
    }

    @Test func dayIsFormattedForTheLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = PuzzleDay(year: 2026, month: 9, day: 29)
        #expect(PuzzleLayout.dateText(day, calendar: calendar, locale: Locale(identifier: "en_US")) == "Sep 29, 2026")
    }
}
