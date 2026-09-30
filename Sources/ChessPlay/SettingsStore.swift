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

/// Per-device settings, stored as JSON under `OpenChess.settings.v1`.
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

    public init() {}

    /// Missing keys and values this build does not know keep their defaults, so saved
    /// settings from older or newer builds never reset everything.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func optional<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        let defaults = AppSettings()
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
    }

    /// The chosen board theme, or the catalog default when none is chosen or the id is unknown.
    public func boardTheme(in catalog: ContentCatalog) -> BoardTheme? {
        boardTheme.flatMap(catalog.boardTheme(id:)) ?? catalog.boardTheme(id: catalog.defaults.boardThemeID)
    }

    /// The chosen piece set, or the catalog default when none is chosen or the id is unknown.
    public func pieceSet(in catalog: ContentCatalog) -> PieceSet? {
        pieceSet.flatMap(catalog.pieceSet(id:)) ?? catalog.pieceSet(id: catalog.defaults.pieceSetID)
    }
}

/// Persists `AppSettings` as JSON under one UserDefaults key. Settings are per device.
@Observable
@MainActor
public final class SettingsStore {
    public static let defaultsKey = "OpenChess.settings.v1"
    /// `@AppStorage` keys of the Play Bots screen before the choice moved into `AppSettings`.
    public static let legacyPlayBotsBotIDKey = "OpenChess.playBots.botID"
    public static let legacyPlayBotsColorKey = "OpenChess.playBots.color"

    public var value: AppSettings { didSet { save() } }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
        var settings = stored.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        let migrated = Self.migrateLegacyPlayBots(into: &settings, storedData: stored, defaults: defaults)
        value = settings
        if migrated { save() }
    }

    /// The sound effects switch.
    public var soundEnabled: Bool {
        get { value.soundEffects }
        set { value.soundEffects = newValue }
    }

    /// Copies the legacy Play Bots keys into `settings` for each field the stored settings lack.
    /// Returns true when anything was copied.
    private static func migrateLegacyPlayBots(
        into settings: inout AppSettings, storedData: Data?, defaults: UserDefaults
    ) -> Bool {
        let storedKeys = storedData
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .map { Set($0.keys) } ?? []
        var migrated = false
        if !storedKeys.contains("playBotsBotID"), let botID = defaults.string(forKey: legacyPlayBotsBotIDKey) {
            settings.playBotsBotID = botID
            migrated = true
        }
        if !storedKeys.contains("playBotsColor"),
           let color = defaults.string(forKey: legacyPlayBotsColorKey).flatMap(BotColorChoice.init(rawValue:)) {
            settings.playBotsColor = color
            migrated = true
        }
        return migrated
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
