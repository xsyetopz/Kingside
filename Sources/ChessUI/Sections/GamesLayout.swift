import ChessContent
import ChessCore
import ChessPlay
import Foundation

/// The text of the Games list rows, apart from the views.
enum GamesLayout {
    /// The opponent in a bot game; both players in pass-and-play.
    static func title(_ game: SavedGame, localization: Localization) -> String {
        guard let human = game.humanColor else {
            return localization.string("games.row.versus", game.white.name, game.black.name)
        }
        return game.player(human.opponent).name
    }

    /// Result and move count and date, such as "You Won! · 31 moves · Jan 15, 2026". When it
    /// wraps, it wraps only after a separator: no part is split, and no line starts with "·".
    static func detail(_ game: SavedGame, localization: Localization, locale: Locale) -> String {
        let nonBreaking = { (part: String) in part.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return localization.string(
            "games.row.detail", nonBreaking(state(game, localization: localization)),
            nonBreaking(localization.plural("common.moves", count: moveCount(game))),
            nonBreaking(game.updatedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))))
            .replacingOccurrences(of: " · ", with: "\u{00A0}· ")
    }

    /// The result title, or "In Progress" for a game that is not over.
    static func state(_ game: SavedGame, localization: Localization) -> String {
        let key = GameSession.resultTitleKey(game.result, humanColor: game.humanColor) ?? "games.status.inProgress"
        return localization.string(key)
    }

    /// Full moves played: a move is one turn of each side, so a last move by White counts.
    static func moveCount(_ game: SavedGame) -> Int { (game.game.moves.count + 1) / 2 }
}
