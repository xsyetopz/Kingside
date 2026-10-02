import ChessContent
import ChessCore

/// Everything needed to start a new game. Built by Play Bots and Play a Friend.
public struct GameSetup: Hashable, Sendable {
  public var mode: GameMode
  public var white: PlayerInfo
  public var black: PlayerInfo
  public var timeControl: TimeControl
  /// Pass-and-play: turn the board to the side to move after each move.
  public var autoFlip: Bool

  public init(
    mode: GameMode,
    white: PlayerInfo,
    black: PlayerInfo,
    timeControl: TimeControl,
    autoFlip: Bool = false
  ) {
    self.mode = mode
    self.white = white
    self.black = black
    self.timeControl = timeControl
    self.autoFlip = autoFlip
  }

  /// An untimed game of the player against `bot`.
  public static func versus(
    _ bot: Bot,
    humanColor: PieceColor,
    localization: Localization
  ) -> Self {
    let human = PlayerInfo(name: localization.string("player.you.name"))
    let botPlayer = PlayerInfo(bot: bot, localization: localization)
    return Self(
      mode: .bot(id: bot.id),
      white: humanColor == .white ? human : botPlayer,
      black: humanColor == .white ? botPlayer : human,
      timeControl: .untimed
    )
  }
}

/// How the game screen starts: a fresh game or a saved one.
public enum GameLaunch: Hashable, Sendable {
  case new(GameSetup)
  case saved(SavedGame)
}
