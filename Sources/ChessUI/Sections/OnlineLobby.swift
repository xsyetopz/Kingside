import ChessContent
import ChessPlay
import LichessLink

/// The parts of the online lobby that need no UI, so tests can reach them.
enum OnlineLobby {
  /// Lichess speed categories the lobby offers. Board API seeks allow only `rapid` and `classical`.
  enum Category: String, CaseIterable {
    case blitz, rapid, classical

    /// Localisation key of the category's name.
    var nameKey: String { "timeControl.category.\(rawValue).name" }
  }

  struct Preset: Hashable, Identifiable {
    let category: Category
    let minutes: Int
    let increment: Int

    var id: String { "\(minutes)+\(increment)" }
    var limitSeconds: Int { minutes * 60 }
  }

  static let seekPresets = [
    Preset(category: .rapid, minutes: 10, increment: 0),
    Preset(category: .rapid, minutes: 10, increment: 5),
    Preset(category: .rapid, minutes: 15, increment: 10),
    Preset(category: .classical, minutes: 30, increment: 0),
    Preset(category: .classical, minutes: 30, increment: 20),
  ]

  static let challengePresets = [
    Preset(category: .blitz, minutes: 3, increment: 2),
    Preset(category: .blitz, minutes: 5, increment: 3),
    Preset(category: .rapid, minutes: 10, increment: 0),
    Preset(category: .rapid, minutes: 15, increment: 10),
    Preset(category: .classical, minutes: 30, increment: 0),
  ]

  /// `presets` that belong to `category`, in order.
  static func presets(_ presets: [Preset], in category: Category) -> [Preset] {
    presets.filter { $0.category == category }
  }

  /// The categories that have a preset in `presets`, in the order they first appear.
  static func categories(of presets: [Preset]) -> [Category] {
    Category.allCases.filter { category in presets.contains { $0.category == category } }
  }

  /// A Lichess username is 2 to 30 letters, digits, underscores or hyphens.
  static func isValidUsername(_ name: String) -> Bool {
    (2...30).contains(name.utf8.count)
      && name.utf8.allSatisfy {
        ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
          || $0 == 0x5F || $0 == 0x2D
      }
  }

  static func label(_ preset: Preset, localization: Localization) -> String {
    label(
      limitSeconds: preset.limitSeconds,
      increment: preset.increment,
      localization: localization
    )
  }

  /// `10 min`, `15 | 10`, or in seconds for a clock that is not a whole number of minutes.
  static func label(limitSeconds: Int, increment: Int, localization: Localization) -> String {
    if limitSeconds.isMultiple(of: 60) {
      let minutes = limitSeconds / 60
      return increment == 0
        ? localization.string("online.timeControl.minutes", minutes)
        : localization.string("online.timeControl.clock", minutes, increment)
    }
    return increment == 0
      ? localization.string("online.timeControl.seconds", limitSeconds)
      : localization.string("online.timeControl.secondsClock", limitSeconds, increment)
  }

  /// The time control of a challenge, which may also be correspondence or unlimited.
  static func label(_ timeControl: LichessTimeControl, localization: Localization) -> String {
    switch timeControl.type {
    case "clock":
      guard let limit = timeControl.limit else { return localization("timeControl.untimed.label") }
      return label(
        limitSeconds: limit,
        increment: timeControl.increment ?? 0,
        localization: localization
      )
    case "correspondence":
      return localization.string("online.timeControl.days", timeControl.daysPerTurn ?? 0)
    default:
      return localization("timeControl.untimed.label")
    }
  }

  /// The challenger's name, with the rating when Lichess gives one.
  static func name(_ user: LichessChallengeUser, localization: Localization) -> String {
    user.rating.map { localization.string("online.challenger", user.name, String($0)) } ?? user.name
  }

  /// Whose turn it is in an ongoing game, as a localisation key.
  static func turnKey(_ game: LichessOngoingGame) -> String {
    game.isMyTurn ? "game.turn.yours" : "game.turn.opponent"
  }

  /// Localisation key of the color the user plays.
  static func colorKey(_ color: LichessColor) -> String { "playBots.color.\(color.rawValue).name" }
}

extension BotColorChoice {
  /// The color to ask Lichess for in a challenge.
  var lichessColor: LichessChallengeColor {
    switch self {
    case .white: .white
    case .black: .black
    case .random: .random
    }
  }
}
