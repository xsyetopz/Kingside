import ChessContent
import Foundation
import Observation

/// Which side the board is drawn from.
public enum BoardOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
  case white, black, automatic

  public var id: String { rawValue }

  /// Localisation key of the option's name.
  public var titleKey: String { "settings.orientation.\(rawValue).name" }
}

/// The color the player picks on Play Bots; `random` picks one per game.
public enum BotColorChoice: String, Codable, CaseIterable, Identifiable, Sendable {
  case white, random, black

  public var id: String { rawValue }

  /// Localisation key of the option's name.
  public var titleKey: String { "playBots.color.\(rawValue).name" }
}

/// Per-device settings, stored as JSON under `Kingside.settings.v1`.
public struct AppSettings: Codable, Equatable, Sendable {
  /// `BoardTheme.id`; nil means `ContentDefaults.boardThemeID`. Older builds stored the names
  /// `green`, `brown`, `blue`, and `purple`; they are kept as stored and resolve to the default.
  public var boardTheme: String?
  /// `PieceSet.id`; nil means `ContentDefaults.pieceSetID`.
  public var pieceSet: String?
  public var orientation: BoardOrientation = .automatic
  public var soundEffects = true
  /// Haptics on devices that have them.
  public var haptics = true
  public var moveAnimation = true
  public var showLegalMoves = true
  public var showCoordinates = true
  public var highlightLastMove = true
  /// Promote straight to a queen instead of showing the promotion picker.
  public var autoPromoteToQueen = false
  /// Last bot chosen on Play Bots (`Bot.id`); nil means `ContentDefaults.botID`.
  public var playBotsBotID: String?
  /// Last color chosen on Play Bots.
  public var playBotsColor: BotColorChoice = .white
  /// Linked Chess.com username; nil when no account is linked.
  public var chessComUsername: String?
  /// The first-launch welcome sheet has been shown.
  public var hasSeenWelcome = false
  /// Shows the chat in online games; off hides the panel and every incoming line.
  public var chatEnabled = true

  public init() {}

  /// Missing keys and values this build does not know keep their defaults, so saved
  /// settings from older or newer builds never reset everything.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    func optional<T: Decodable>(_ key: CodingKeys) -> T? {
      (try? container.decodeIfPresent(T.self, forKey: key))
    }
    let defaults = Self()
    boardTheme = optional(.boardTheme)
    pieceSet = optional(.pieceSet)
    orientation = value(.orientation, defaults.orientation)
    soundEffects = value(.soundEffects, defaults.soundEffects)
    haptics = value(.haptics, defaults.haptics)
    moveAnimation = value(.moveAnimation, defaults.moveAnimation)
    showLegalMoves = value(.showLegalMoves, defaults.showLegalMoves)
    showCoordinates = value(.showCoordinates, defaults.showCoordinates)
    highlightLastMove = value(.highlightLastMove, defaults.highlightLastMove)
    autoPromoteToQueen = value(.autoPromoteToQueen, defaults.autoPromoteToQueen)
    playBotsBotID = optional(.playBotsBotID)
    playBotsColor = value(.playBotsColor, defaults.playBotsColor)
    chessComUsername = optional(.chessComUsername)
    hasSeenWelcome = value(.hasSeenWelcome, defaults.hasSeenWelcome)
    chatEnabled = value(.chatEnabled, defaults.chatEnabled)
  }

  /// The chosen board theme, or the catalog default when none is chosen or the id is unknown.
  public func boardTheme(in catalog: ContentCatalog) -> BoardTheme? {
    boardTheme.flatMap(catalog.boardTheme(id:))
      ?? catalog.boardTheme(id: catalog.defaults.boardThemeID)
  }

  /// The chosen piece set, or the catalog default when none is chosen or the id is unknown.
  public func pieceSet(in catalog: ContentCatalog) -> PieceSet? {
    pieceSet.flatMap(catalog.pieceSet(id:)) ?? catalog.pieceSet(id: catalog.defaults.pieceSetID)
  }
}

/// Persists `AppSettings` as JSON under one UserDefaults key. Settings are per device.
@preconcurrency
@Observable
@MainActor
public final class SettingsStore {
  public static let defaultsKey = "Kingside.settings.v1"

  public var value: AppSettings { didSet { save() } }
  private let defaults: UserDefaults

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    value =
      defaults.data(forKey: Self.defaultsKey)
      .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
  }

  /// The sound effects switch.
  public var soundEffects: Bool {
    get { value.soundEffects }
    set { value.soundEffects = newValue }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.defaultsKey) }
  }
}
