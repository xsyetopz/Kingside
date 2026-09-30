import ChessContent
import ChessCore
import Foundation

// Stored game model shared by the game screen, Resume, the archive, and Game Review.
// The Codable shapes are those of `saved-games-v2.json`; data written by older builds must
// keep decoding.

/// How a game is played.
public enum GameMode: Codable, Hashable, Sendable {
    /// Against a catalog bot; `id` is `ChessContent.Bot.id`.
    case bot(id: String)
    /// Two people sharing one device.
    case passAndPlay
    /// On an online service, such as `lichess`; `gameID` is the service's game id.
    case online(service: String, gameID: String)

    public var botID: String? {
        if case .bot(let id) = self { return id }
        return nil
    }

    /// The human's side: the non-bot side in a bot game, the `PlayerInfo.isLocalUser` side in
    /// an online game, nil in pass-and-play (and in an online game with no marked side).
    public func humanColor(white: PlayerInfo, black: PlayerInfo) -> PieceColor? {
        switch self {
        case .bot: white.isBot ? .black : .white
        case .passAndPlay: nil
        case .online: white.isLocalUser ? .white : (black.isLocalUser ? .black : nil)
        }
    }
}

/// One side of a game as shown in player bars and PGN tags.
public struct PlayerInfo: Codable, Hashable, Sendable {
    public var name: String
    /// Elo-like rating; bots have one, local humans usually do not.
    public var rating: Int?
    /// `Bot.id` when this side is played by a bot, nil for a human.
    public var botID: String?
    /// Online games: true on the side the signed-in player played. Not stored when false, so
    /// bot and pass-and-play games keep their old encoding.
    public var isLocalUser: Bool {
        get { localUser ?? false }
        set { localUser = newValue ? true : nil }
    }
    private var localUser: Bool?

    public init(name: String, rating: Int? = nil, botID: String? = nil, isLocalUser: Bool = false) {
        self.name = name
        self.rating = rating
        self.botID = botID
        self.isLocalUser = isLocalUser
    }

    /// `bot` as a player, with its localised name and its Elo.
    public init(bot: Bot, localization: Localization) {
        self.init(name: localization.string(bot.nameKey), rating: bot.elo, botID: bot.id)
    }

    public var isBot: Bool { botID != nil }
}

/// The clock setting a game was played with. `initialSeconds == 0` means no timer.
/// The offered presets, their labels, and categories are in `ContentCatalog.timeControls`.
public struct TimeControl: Codable, Hashable, Sendable {
    public var initialSeconds: Int
    public var incrementSeconds: Int

    public init(initialSeconds: Int, incrementSeconds: Int) {
        self.initialSeconds = initialSeconds
        self.incrementSeconds = incrementSeconds
    }

    public init(_ preset: TimeControlPreset) {
        self.init(initialSeconds: preset.initialSeconds, incrementSeconds: preset.incrementSeconds)
    }

    public static let untimed = TimeControl(initialSeconds: 0, incrementSeconds: 0)

    public var isTimed: Bool { initialSeconds > 0 }

    /// PGN `TimeControl` tag value, such as `180+2`; `-` when untimed.
    public var pgnValue: String {
        guard isTimed else { return "-" }
        return incrementSeconds > 0 ? "\(initialSeconds)+\(incrementSeconds)" : "\(initialSeconds)"
    }

    /// The catalog preset with the same times, if one is offered.
    public func preset(in catalog: TimeControlCatalog) -> TimeControlPreset? {
        catalog.presets.first { $0.initialSeconds == initialSeconds && $0.incrementSeconds == incrementSeconds }
    }
}

/// Final or current result of a game.
public enum GameResult: String, Codable, Sendable {
    case whiteWon, blackWon, draw, ongoing

    /// PGN result token: "1-0", "0-1", "1/2-1/2" or "*".
    public var pgnValue: String {
        switch self {
        case .whiteWon: "1-0"
        case .blackWon: "0-1"
        case .draw: "1/2-1/2"
        case .ongoing: "*"
        }
    }

    public var winner: PieceColor? {
        switch self {
        case .whiteWon: .white
        case .blackWon: .black
        case .draw, .ongoing: nil
        }
    }

    public static func win(for color: PieceColor) -> GameResult { color == .white ? .whiteWon : .blackWon }
}

/// Why a finished game ended.
public enum GameTermination: String, CaseIterable, Codable, Sendable {
    case checkmate, timeout, resignation, stalemate, repetition, insufficientMaterial, agreement
    case fiftyMoveRule, timeoutVsInsufficientMaterial

    /// Localisation key of the reason line on the game-over card, such as "by checkmate".
    public var reasonKey: String { "game.termination.\(rawValue).reason" }

    /// English reason for the PGN `Termination` tag, which is not localised.
    var pgnReason: String {
        switch self {
        case .checkmate: "by checkmate"
        case .timeout: "on time"
        case .resignation: "by resignation"
        case .stalemate: "by stalemate"
        case .repetition: "by repetition"
        case .insufficientMaterial: "by insufficient material"
        case .agreement: "by agreement"
        case .fiftyMoveRule: "by 50-move rule"
        case .timeoutVsInsufficientMaterial: "timeout vs insufficient material"
        }
    }
}

/// A local game, saved while in progress (for Resume) and after it ends (for the archive).
public struct SavedGame: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var createdAt: Date
    /// Last save time; the store sorts newest first by this date.
    public var updatedAt: Date
    public var mode: GameMode
    public var white: PlayerInfo
    public var black: PlayerInfo
    public var timeControl: TimeControl
    /// Pass-and-play option: the board turns to the side to move after each move.
    public var autoFlip: Bool
    /// Moves and positions, starting from the standard initial position.
    public var game: ChessGame
    public var result: GameResult
    /// Set once the game has ended; nil while it is ongoing.
    public var termination: GameTermination?
    /// Remaining time of both sides at the last save; used to resume timed games.
    public var clock: GameClock

    public init(
        id: UUID = UUID(), createdAt: Date, updatedAt: Date, mode: GameMode, white: PlayerInfo, black: PlayerInfo,
        timeControl: TimeControl, autoFlip: Bool, game: ChessGame, result: GameResult,
        termination: GameTermination?, clock: GameClock
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.white = white
        self.black = black
        self.timeControl = timeControl
        self.autoFlip = autoFlip
        self.game = game
        self.result = result
        self.termination = termination
        self.clock = clock
    }

    public var isFinished: Bool { result != .ongoing }

    public func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

    /// The human's color in a bot or online game; nil in pass-and-play. See `GameMode.humanColor`.
    public var humanColor: PieceColor? { mode.humanColor(white: white, black: black) }

    /// PGN with Event, Site, Date, White, Black, Result, TimeControl, Termination and
    /// WhiteElo/BlackElo when known.
    public var pgn: String {
        let event, site: String
        switch mode {
        case .bot: (event, site) = ("Casual Game vs Bot", "Kingside")
        case .passAndPlay: (event, site) = ("Pass and Play", "Kingside")
        case .online(let service, _): (event, site) = ("Online Game", service)
        }
        var tags = [
            "Event": event,
            "Site": site,
            "Date": Self.pgnDate(createdAt),
            "Round": "-",
            "White": white.name,
            "Black": black.name,
            "TimeControl": timeControl.pgnValue
        ]
        if let rating = white.rating { tags["WhiteElo"] = String(rating) }
        if let rating = black.rating { tags["BlackElo"] = String(rating) }
        if let termination { tags["Termination"] = terminationTag(termination) }
        return PGNExporter().export(game: game, tags: tags, result: result.pgnValue)
    }

    private func terminationTag(_ termination: GameTermination) -> String {
        switch result {
        case .whiteWon: "\(white.name) won \(termination.pgnReason)"
        case .blackWon: "\(black.name) won \(termination.pgnReason)"
        case .draw: termination == .timeoutVsInsufficientMaterial
            ? "Game drawn by timeout vs insufficient material"
            : "Game drawn \(termination.pgnReason)"
        case .ongoing: "Unterminated"
        }
    }

    private static func pgnDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

/// Route values compare and hash by content, but `ChessGame` is not `Hashable`; the id is
/// enough because equal games always share it.
extension SavedGame: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
