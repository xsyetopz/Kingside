import ChessComLink
import ChessPlay
import Foundation

/// What one import did.
public struct ChessComImportSummary: Equatable, Sendable {
  public internal(set) var imported = 0
  /// Copies saved by an earlier version, replaced so they show the user's side.
  public internal(set) var updated = 0
  /// Already in the archive.
  public internal(set) var duplicates = 0
  /// Other rules than standard chess, a PGN that does not replay, or a failed save.
  public internal(set) var skipped = 0
}

/// Turns Chess.com games into `SavedGame`s of the local archive.
public enum ChessComImporting {
  /// The `GameMode.online` service of imported games.
  static let service = "chessCom"

  /// Saves each standard-chess game whose id is not stored yet, with `username`'s side as the
  /// local user's. Returns the counts. When the archive cannot be read, nothing can be saved, so
  /// every game counts as skipped.
  ///
  /// Imports used to be saved as pass-and-play with neither side marked. A stored pass-and-play
  /// game with a game's id is such a copy, because games played here get random ids, so it is
  /// replaced and counted as updated. Old copies of `username`'s games that `sources` does not
  /// hold are looked up in the monthly archives `monthGames` returns, by year and month; a month
  /// that fails to load is tried again on the next import.
  @preconcurrency
  public static func importGames(
    _ sources: [ChessComGame],
    username: String,
    into store: GamePersistenceStore,
    monthGames: @Sendable (_ year: Int, _ month: Int) async throws -> [ChessComGame] = { _, _ in
      []
    }
  ) async -> ChessComImportSummary {
    var summary = ChessComImportSummary()
    guard let stored = try? await store.allGames() else {
      summary.skipped = sources.count
      return summary
    }
    var oldCopies = Set(stored.filter { $0.mode == .passAndPlay }.map(\.id))
    var known = Set(stored.map(\.id)).subtracting(oldCopies)
    let importer = ChessComGameImporter()
    func save(_ source: ChessComGame, id: UUID) async -> Bool {
      guard case .imported(let imported)? = try? importer.importGame(source) else { return false }
      return (try? await store.save(savedGame(imported, id: id, username: username))) != nil
    }
    for source in sources {
      let id = savedGameID(for: source.url)
      guard known.insert(id).inserted else {
        summary.duplicates += 1
        continue
      }
      guard await save(source, id: id) else {
        summary.skipped += 1
        continue
      }
      if oldCopies.remove(id) != nil { summary.updated += 1 } else { summary.imported += 1 }
    }
    let remaining = stored.filter { oldCopies.contains($0.id) && isOldCopy($0, of: username) }
    for (year, month) in archiveMonths(of: remaining) {
      guard let games = try? await monthGames(year, month) else { continue }
      for source in games {
        let id = savedGameID(for: source.url)
        guard oldCopies.contains(id), await save(source, id: id) else { continue }
        oldCopies.remove(id)
        summary.updated += 1
      }
    }
    return summary
  }

  /// Whether `game` can be an import of `username`'s saved by an earlier version: pass-and-play
  /// with `username` playing. Only the id tells for sure.
  static func isOldCopy(_ game: SavedGame, of username: String) -> Bool {
    game.mode == .passAndPlay
      && [game.white.name, game.black.name].contains {
        $0.caseInsensitiveCompare(username) == .orderedSame
      }
  }

  /// The archive months, oldest first, that can hold each game. A game was saved with its end
  /// time; Chess.com files it by a month that this code does not know the time zone of, so the
  /// months of every zone (UTC−12 to UTC+14) count.
  static func archiveMonths(of games: [SavedGame]) -> [(year: Int, month: Int)] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let months = Set(
      games.flatMap { game in
        [-12.0, 0, 14].map { hours in
          let date = game.createdAt.addingTimeInterval(hours * 3600)
          return calendar.component(.year, from: date) * 100
            + calendar.component(.month, from: date)
        }
      }
    )
    return months.sorted().map { ($0 / 100, $0 % 100) }
  }

  /// Both players are named as on Chess.com. `username`'s side is the local user's, so the
  /// archive and Game Review show the game from that side; a game without `username` has none.
  static func savedGame(_ imported: ChessComImportedGame, id: UUID, username: String) -> SavedGame {
    let source = imported.source
    let timeControl = timeControl(source.timeControl)
    let result = result(white: source.white.result, black: source.black.result)
    return SavedGame(
      id: id,
      createdAt: source.endTime,
      updatedAt: source.endTime,
      mode: .online(service: service, gameID: source.url.lastPathComponent),
      white: PlayerInfo(
        name: source.white.username,
        rating: source.white.rating,
        isLocalUser: source.white.isUser(username)
      ),
      black: PlayerInfo(
        name: source.black.username,
        rating: source.black.rating,
        isLocalUser: !source.white.isUser(username) && source.black.isUser(username)
      ),
      timeControl: timeControl,
      autoFlip: false,
      game: imported.game,
      result: result,
      termination: termination(white: source.white.result, black: source.black.result),
      clock: GameClock(timeControl: timeControl)
    )
  }

  /// The same game always gets the same id, so importing twice finds the first copy. The id is two
  /// FNV-1a hashes of the game's URL.
  static func savedGameID(for url: URL) -> UUID {
    func fnv(_ offset: UInt64) -> UInt64 {
      url.absoluteString.utf8.reduce(offset) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
    let (high, low) = (fnv(0xCBF2_9CE4_8422_2325), fnv(0x84222325_CBF29CE4))
    let bytes =
      (0..<8).map { UInt8(truncatingIfNeeded: high >> ($0 * 8)) }
      + (0..<8).map { UInt8(truncatingIfNeeded: low >> ($0 * 8)) }
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      )
    )
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
  public static func result(white: ChessComPlayerResult, black: ChessComPlayerResult) -> GameResult
  {
    if white == .win { return .whiteWon }
    if black == .win { return .blackWon }
    return .draw
  }

  /// From the code of the side that did not win, or of White in a draw; nil for codes with no
  /// match.
  static func termination(
    white: ChessComPlayerResult,
    black: ChessComPlayerResult
  ) -> GameTermination? {
    switch white == .win ? black : white {
    case .checkmated: .checkmate
    case .timeout: .timeout
    case .resigned: .resignation
    case .stalemate: .stalemate
    case .repetition: .repetition
    case .insufficient: .insufficientMaterial
    case .agreed: .agreement
    case .fiftyMove: .fiftyMoveRule
    case .timeVsInsufficient: .timeoutVsInsufficientMaterial
    case .win, .other: nil
    }
  }
}
