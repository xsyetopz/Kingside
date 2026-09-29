import Foundation
import ChessCore

/// Everything needed to start a new game. Built by Play Bots and Play a Friend.
struct GameSetup: Hashable, Sendable {
    var mode: GameMode
    var white: PlayerInfo
    var black: PlayerInfo
    var timeControl: TimeControl
    /// Pass-and-play: turn the board to the side to move after each move.
    var autoFlip = false

    static func versus(_ bot: Bot, humanColor: PieceColor) -> GameSetup {
        let human = PlayerInfo(name: "You")
        return GameSetup(
            mode: .bot(id: bot.id),
            white: humanColor == .white ? human : bot.playerInfo,
            black: humanColor == .white ? bot.playerInfo : human,
            timeControl: .untimed
        )
    }

    /// Same players with colors swapped.
    var swapped: GameSetup {
        var copy = self
        copy.white = black
        copy.black = white
        return copy
    }
}

/// How the game screen starts: a fresh game or a saved one.
enum GameLaunch: Hashable {
    case new(GameSetup)
    case saved(SavedGame)
}
