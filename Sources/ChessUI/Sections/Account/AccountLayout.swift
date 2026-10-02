import ChessComLink
import ChessComPlay
import ChessContent
import ChessCore
import ChessOnline
import ChessPlay
import Foundation

/// The text and rows of the Account screen, apart from the views.
enum AccountLayout {
  struct RatingRow: Equatable, Identifiable {
    /// `rapid`, `blitz`, `bullet` or `daily`.
    let timeClass: String
    let rating: Int
    let record: ChessComStats.Record?

    var id: String { timeClass }
  }

  /// Localisation key of what to tell the player when Game Center is unavailable. GameKit
  /// authenticates once per launch, so the texts do not offer a retry in the app.
  static func gameCenterDetailKey(_ reason: GameCenterUnavailableReason) -> String {
    switch reason {
    case .restricted: "account.gameCenter.unavailable.restricted"
    case .offline: "account.gameCenter.unavailable.offline"
    case .notSetUp: "account.gameCenter.unavailable.notSetUp"
    case .other: "account.gameCenter.unavailable.other"
    }
  }

  /// The time classes the player has a rating in, in the order Chess.com lists them.
  static func ratings(_ stats: ChessComStats) -> [RatingRow] {
    [
      ("rapid", stats.rapid), ("blitz", stats.blitz), ("bullet", stats.bullet),
      ("daily", stats.daily),
    ]
    .compactMap { timeClass, mode in
      mode?.last.map { RatingRow(timeClass: timeClass, rating: $0.rating, record: mode?.record) }
    }
  }

  static func timeClassName(_ timeClass: String, localization: Localization) -> String {
    localization.string(
      "account.chessCom.timeClass.\(timeClass)",
      defaultValue: timeClass.capitalized
    )
  }

  static func record(_ record: ChessComStats.Record, localization: Localization) -> String {
    localization.string("account.chessCom.record", record.win, record.loss, record.draw)
  }

  /// The side `username` played, ignoring case; nil when neither side is theirs.
  static func color(of username: String, in game: ChessComGame) -> PieceColor? {
    if game.white.username.caseInsensitiveCompare(username) == .orderedSame { return .white }
    if game.black.username.caseInsensitiveCompare(username) == .orderedSame { return .black }
    return nil
  }

  /// The opponent with their rating, such as "hikaru (3200)"; both players when neither is
  /// `username`.
  static func title(_ game: ChessComGame, username: String, localization: Localization) -> String {
    func name(_ player: ChessComGame.Player) -> String { "\(player.username) (\(player.rating))" }
    switch color(of: username, in: game) {
    case .white?: return name(game.black)
    case .black?: return name(game.white)
    case nil: return localization.string("games.row.versus", name(game.white), name(game.black))
    }
  }

  /// Result from `username`'s side, time class, and date.
  static func detail(
    _ game: ChessComGame,
    username: String,
    localization: Localization,
    locale: Locale
  ) -> String {
    let result = ChessComImporting.result(white: game.white.result, black: game.black.result)
    let key =
      GameSession.resultTitleKey(result, humanColor: color(of: username, in: game))
      ?? "games.status.inProgress"
    return localization.string(
      "account.chessCom.game.detail",
      localization.string(key),
      timeClassName(game.timeClass, localization: localization),
      game.endTime.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    )
  }

  /// One line for each count the import produced, such as "3 games imported".
  static func summaryLines(_ summary: ChessComImportSummary, localization: Localization) -> [String]
  {
    [
      ("account.chessCom.imported", summary.imported),
      ("account.chessCom.duplicates", summary.duplicates),
      ("account.chessCom.skipped", summary.skipped),
    ]
    .filter { $0.1 > 0 }
    .map { localization.plural($0.0, count: $0.1) }
  }
}
