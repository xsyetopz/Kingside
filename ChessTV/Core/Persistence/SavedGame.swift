import Foundation
import ChessCore

// Stored game model shared by the game screen, Resume, the archive and Game Review.
// - `SavedGame`: one game, in progress or finished. `pgn` exports it with standard tags.
// - `GameMode`: `.bot(id:)` (id from `BotRoster`) or `.passAndPlay`.
// - `PlayerInfo`: name, optional rating, and `botID` when the player is a bot.
// - `TimeControl`: base time plus increment in seconds; `.untimed` has no clock.
// - `GameResult` / `GameTermination`: who won and why.
// - Clock state for resume lives in `clock` (`GameClock`, see Features/Game/GameClock.swift).

/// How a game is played.
enum GameMode: Codable, Hashable, Sendable {
    /// Against a roster bot; `id` is `Bot.id`.
    case bot(id: String)
    /// Two people sharing the remote.
    case passAndPlay

    var botID: String? {
        if case .bot(let id) = self { return id }
        return nil
    }
}

/// One side of a game as shown in player bars and PGN tags.
struct PlayerInfo: Codable, Hashable, Sendable {
    var name: String
    /// Elo-like rating; bots have one, local humans usually do not.
    var rating: Int?
    /// `Bot.id` when this side is played by a bot, nil for a human.
    var botID: String?

    var isBot: Bool { botID != nil }
}

/// Chess clock settings. `initialSeconds == 0` means no timer.
struct TimeControl: Codable, Hashable, Sendable {
    enum Category: String, Codable, Sendable {
        case bullet, blitz, rapid, untimed
        var title: String { rawValue.capitalized }
    }

    var initialSeconds: Int
    var incrementSeconds: Int

    static let untimed = TimeControl(initialSeconds: 0, incrementSeconds: 0)

    var isTimed: Bool { initialSeconds > 0 }

    /// Bullet under 3 minutes, blitz under 10, rapid otherwise; estimated over 40 moves.
    var category: Category {
        guard isTimed else { return .untimed }
        let estimate = initialSeconds + 40 * incrementSeconds
        if estimate < 180 { return .bullet }
        if estimate < 600 { return .blitz }
        return .rapid
    }

    /// "3 | 2" with an increment, "10 min" without, "No timer" when untimed.
    var label: String {
        guard isTimed else { return "No timer" }
        let minutes = initialSeconds / 60
        return incrementSeconds > 0 ? "\(minutes) | \(incrementSeconds)" : "\(minutes) min"
    }

    /// PGN `TimeControl` tag value, e.g. "180+2"; "-" when untimed.
    var pgnValue: String {
        guard isTimed else { return "-" }
        return incrementSeconds > 0 ? "\(initialSeconds)+\(incrementSeconds)" : "\(initialSeconds)"
    }

    /// Tiles offered on the Play a Friend screen, grouped by category.
    static let presets: [TimeControl] = [
        TimeControl(initialSeconds: 60, incrementSeconds: 0),
        TimeControl(initialSeconds: 60, incrementSeconds: 1),
        TimeControl(initialSeconds: 120, incrementSeconds: 1),
        TimeControl(initialSeconds: 180, incrementSeconds: 0),
        TimeControl(initialSeconds: 180, incrementSeconds: 2),
        TimeControl(initialSeconds: 300, incrementSeconds: 0),
        TimeControl(initialSeconds: 600, incrementSeconds: 0),
        TimeControl(initialSeconds: 900, incrementSeconds: 10),
        TimeControl(initialSeconds: 1800, incrementSeconds: 0)
    ]
}

/// Final or current result of a game.
enum GameResult: String, Codable, Sendable {
    case whiteWon, blackWon, draw, ongoing

    /// PGN result token: "1-0", "0-1", "1/2-1/2" or "*".
    var pgnValue: String {
        switch self {
        case .whiteWon: "1-0"
        case .blackWon: "0-1"
        case .draw: "1/2-1/2"
        case .ongoing: "*"
        }
    }

    var winner: PieceColor? {
        switch self {
        case .whiteWon: .white
        case .blackWon: .black
        case .draw, .ongoing: nil
        }
    }

    static func win(for color: PieceColor) -> GameResult { color == .white ? .whiteWon : .blackWon }
}

/// Why a finished game ended.
enum GameTermination: String, Codable, Sendable {
    case checkmate, timeout, resignation, stalemate, repetition, insufficientMaterial, agreement
    case fiftyMoveRule, timeoutVsInsufficientMaterial

    /// Reason line for the game-over card, e.g. "by checkmate".
    var reasonText: String {
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
struct SavedGame: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var createdAt: Date
    /// Last save time; the store sorts newest first by this date.
    var updatedAt: Date
    var mode: GameMode
    var white: PlayerInfo
    var black: PlayerInfo
    var timeControl: TimeControl
    /// Pass-and-play option: the board turns to the side to move after each move.
    var autoFlip: Bool
    /// Moves and positions, starting from the standard initial position.
    var game: ChessGame
    var result: GameResult
    /// Set once the game has ended; nil while it is ongoing.
    var termination: GameTermination?
    /// Remaining time of both sides at the last save; used to resume timed games.
    var clock: GameClock

    var isFinished: Bool { result != .ongoing }

    func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

    /// The human's color in a bot game; nil in pass-and-play.
    var humanColor: PieceColor? {
        guard mode.botID != nil else { return nil }
        return white.isBot ? .black : .white
    }

    /// PGN with Event, Site, Date, White, Black, Result, TimeControl, Termination and
    /// WhiteElo/BlackElo when known.
    var pgn: String {
        var tags = [
            "Event": mode.botID == nil ? "Pass and Play" : "Casual Game vs Bot",
            "Site": "ChessTV",
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
        case .whiteWon: "\(white.name) won \(termination.reasonText)"
        case .blackWon: "\(black.name) won \(termination.reasonText)"
        case .draw: termination == .timeoutVsInsufficientMaterial
            ? "Game drawn by timeout vs insufficient material"
            : "Game drawn \(termination.reasonText)"
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
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
