import ChessCore
import ChessPlay
import Foundation

/// The puzzle screens' texts and symbols, apart from the views.
enum PuzzleLayout {
    /// The localization key of the status line for a board `phase`. The solver's turn names the
    /// color, and the opponent's turn, including the opening move, reuses the game's line.
    static func statusKey(phase: PuzzleSession.Phase, solverColor: PieceColor) -> String {
        switch phase {
        case .intro, .opponentToMove: "game.turn.opponent"
        case .solverToMove: solverColor == .white ? "game.turn.white" : "game.turn.black"
        case .solved: "puzzles.status.solved"
        case .failed: "puzzles.status.failed"
        case .revealing: "puzzles.status.revealing"
        case .revealed: "puzzles.status.revealed"
        }
    }

    /// A rating change with its sign: `+12`, `-8`, `0`.
    static func ratingChangeText(_ change: Int) -> String {
        change > 0 ? "+\(change)" : "\(change)"
    }

    /// The SF Symbol of a Puzzle Rush mode.
    static func symbol(for mode: PuzzleRushMode) -> String {
        switch mode {
        case .threeMinutes: "bolt"
        case .fiveMinutes: "timer"
        case .survival: "heart"
        }
    }

    /// `day` as a date for people, such as "Sep 29, 2026".
    static func dateText(_ day: PuzzleDay, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        guard let date = calendar.date(from: components) else { return day.key }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }
}
