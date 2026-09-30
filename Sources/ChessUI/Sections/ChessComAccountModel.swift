import ChessComLink
import ChessCore
import ChessPlay
import Foundation
import Observation

/// Why a Chess.com request failed, as the Account screens word it.
enum ChessComFailure: Error, Equatable {
    case invalidUsername, notFound, rateLimited, network

    init(_ error: any Error) {
        switch error as? ChessComError {
        case .invalidUsername?: self = .invalidUsername
        case .notFound?: self = .notFound
        case .rateLimited?: self = .rateLimited
        default: self = .network
        }
    }

    /// Localisation key of the message.
    var messageKey: String {
        switch self {
        case .invalidUsername: "account.chessCom.error.invalidUsername"
        case .notFound: "account.chessCom.error.notFound"
        case .rateLimited: "account.chessCom.error.rateLimited"
        case .network: "account.chessCom.error.network"
        }
    }
}

/// What one import did.
struct ChessComImportSummary: Equatable {
    var imported = 0
    /// Already in the archive.
    var duplicates = 0
    /// Other rules than standard chess, a PGN that does not replay, or a failed save.
    var skipped = 0
}

/// The linked Chess.com account: profile, stats and the latest games, read from the public PubAPI.
@Observable
@MainActor
final class ChessComAccountModel {
    enum Phase: Equatable {
        case loading, loaded
        case failed(ChessComFailure)
    }

    let username: String
    private(set) var phase = Phase.loading
    private(set) var profile: ChessComProfile?
    private(set) var stats: ChessComStats?
    /// The latest archive, newest first.
    private(set) var games: [ChessComGame] = []
    private(set) var importSummary: ChessComImportSummary?

    private let client: ChessComClient
    private let gameLimit: Int

    init(username: String, client: ChessComClient, gameLimit: Int) {
        self.username = username
        self.client = client
        self.gameLimit = gameLimit
    }

    func load() async {
        phase = .loading
        do {
            profile = try await client.profile(username: username)
            stats = try await client.stats(username: username)
            let archives = try await client.archives(username: username)
            var latest: [ChessComGame] = []
            if let archive = archives.last { latest = try await client.games(archiveURL: archive) }
            games = Array(latest.sorted { $0.endTime > $1.endTime }.prefix(gameLimit))
            phase = .loaded
        } catch {
            phase = .failed(ChessComFailure(error))
        }
    }

    /// Saves `sources` that are not in the archive yet, and reports what happened.
    func importGames(_ sources: [ChessComGame], into store: GamePersistenceStore) async {
        importSummary = await ChessComImporting.importGames(sources, username: username, into: store)
    }

    /// The profile of `username`, or why it cannot be linked.
    static func verify(username: String, client: ChessComClient) async -> Result<ChessComProfile, ChessComFailure> {
        do {
            return .success(try await client.profile(username: username))
        } catch {
            return .failure(ChessComFailure(error))
        }
    }
}

/// Turns Chess.com games into `SavedGame`s of the local archive.
enum ChessComImporting {
    /// Saves each standard-chess game whose id is not stored yet. Returns the counts. When the
    /// archive cannot be read, nothing can be saved, so every game counts as skipped.
    static func importGames(
        _ sources: [ChessComGame], username: String, into store: GamePersistenceStore
    ) async -> ChessComImportSummary {
        var summary = ChessComImportSummary()
        guard let stored = try? await store.allGames() else {
            summary.skipped = sources.count
            return summary
        }
        var known = Set(stored.map(\.id))
        let importer = ChessComGameImporter()
        for source in sources {
            let id = savedGameID(for: source.url)
            guard known.insert(id).inserted else {
                summary.duplicates += 1
                continue
            }
            guard case .imported(let imported)? = try? importer.importGame(source),
                  (try? await store.save(savedGame(imported, id: id))) != nil
            else {
                summary.skipped += 1
                continue
            }
            summary.imported += 1
        }
        return summary
    }

    /// Both players are named as on Chess.com, so the game reads as one between two people.
    static func savedGame(_ imported: ChessComImportedGame, id: UUID) -> SavedGame {
        let source = imported.source
        let timeControl = timeControl(source.timeControl)
        let result = result(white: source.white.result, black: source.black.result)
        return SavedGame(
            id: id, createdAt: source.endTime, updatedAt: source.endTime, mode: .passAndPlay,
            white: PlayerInfo(name: source.white.username, rating: source.white.rating),
            black: PlayerInfo(name: source.black.username, rating: source.black.rating),
            timeControl: timeControl, autoFlip: false, game: imported.game, result: result,
            termination: termination(white: source.white.result, black: source.black.result),
            clock: GameClock(timeControl: timeControl))
    }

    /// The same game always gets the same id, so importing twice finds the first copy. The id is two
    /// FNV-1a hashes of the game's URL.
    static func savedGameID(for url: URL) -> UUID {
        func fnv(_ offset: UInt64) -> UInt64 {
            url.absoluteString.utf8.reduce(offset) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
        }
        let (high, low) = (fnv(0xCBF2_9CE4_8422_2325), fnv(0x84222325_CBF29CE4))
        let bytes = (0..<8).map { UInt8(truncatingIfNeeded: high >> ($0 * 8)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: low >> ($0 * 8)) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// `600`, `180+2`; daily games (`1/86400`) have no clock here.
    static func timeControl(_ value: String) -> TimeControl {
        let parts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let initial = Int(parts[0]) else { return .untimed }
        let increment = parts.count == 2 ? Int(parts[1]) : 0
        guard let increment else { return .untimed }
        return TimeControl(initialSeconds: initial, incrementSeconds: increment)
    }

    /// Chess.com gives each side a result code; the side with `win` won and any other pair is a draw.
    static func result(white: String, black: String) -> GameResult {
        if white == "win" { return .whiteWon }
        if black == "win" { return .blackWon }
        return .draw
    }

    /// From the code of the side that did not win, or of White in a draw; nil for codes with no match.
    static func termination(white: String, black: String) -> GameTermination? {
        switch white == "win" ? black : white {
        case "checkmated": .checkmate
        case "timeout": .timeout
        case "resigned": .resignation
        case "stalemate": .stalemate
        case "repetition": .repetition
        case "insufficient": .insufficientMaterial
        case "agreed": .agreement
        case "50move": .fiftyMoveRule
        case "timevsinsufficient": .timeoutVsInsufficientMaterial
        default: nil
        }
    }
}
