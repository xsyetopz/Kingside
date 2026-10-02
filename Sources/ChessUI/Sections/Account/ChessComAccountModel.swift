import ChessComLink
import ChessComPlay
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

/// The linked Chess.com account: profile, stats and the latest games, read from the public PubAPI.
/// App-wide, like the Lichess account, and the only writer of the linked username.
@Observable
@MainActor
final class ChessComAccountModel {
  enum Phase: Equatable {
    case loading, loaded
    case failed(ChessComFailure)
  }

  private(set) var phase = Phase.loading
  private(set) var profile: ChessComProfile?
  private(set) var stats: ChessComStats?
  /// The latest archive, newest first.
  private(set) var games: [ChessComGame] = []
  private(set) var importSummary: ChessComImportSummary?

  @ObservationIgnored
  private let settings: SettingsStore
  @ObservationIgnored
  private let client: ChessComClient
  @ObservationIgnored
  private let gameLimit: Int
  /// Bumped by every link, unlink and load. A request applies its result only if nothing newer
  /// started while it ran, so the user's latest action wins, not the slowest response.
  @ObservationIgnored
  private var generation = 0

  init(settings: SettingsStore, client: ChessComClient, gameLimit: Int) {
    self.settings = settings
    self.client = client
    self.gameLimit = gameLimit
  }

  /// The linked username, or nil when no account is linked.
  var username: String? { settings.value.chessComUsername }

  /// Links `username` once its profile exists; the Account screen then loads it. Returns why it
  /// cannot be linked, or nil when it is linked or a later link or unlink replaced this one.
  func link(username: String) async -> ChessComFailure? {
    let current = nextGeneration()
    let profile: ChessComProfile
    do {
      profile = try await client.profile(username: username)
    } catch {
      return current == generation ? ChessComFailure(error) : nil
    }
    guard current == generation else { return nil }
    forget()
    settings.value.chessComUsername = profile.username
    return nil
  }

  func unlink() {
    nextGeneration()
    settings.value.chessComUsername = nil
    forget()
  }

  func load() async {
    guard let name = username else { return }
    let current = nextGeneration()
    phase = .loading
    var fetchedProfile: ChessComProfile?
    var fetchedStats: ChessComStats?
    var latest: [ChessComGame] = []
    let outcome: Phase
    do {
      fetchedProfile = try await client.profile(username: name)
      fetchedStats = try await client.stats(username: name)
      let archives = try await client.archives(username: name)
      if let archive = archives.last { latest = try await client.games(archiveURL: archive) }
      outcome = .loaded
    } catch {
      outcome = .failed(ChessComFailure(error))
    }
    guard current == generation, !Task.isCancelled else { return }
    profile = fetchedProfile
    stats = fetchedStats
    games = Array(latest.sorted { $0.endTime > $1.endTime }.prefix(gameLimit))
    phase = outcome
  }

  /// Saves `sources` that are not in the archive yet, and reports what happened.
  func importGames(_ sources: [ChessComGame], into store: GamePersistenceStore) async {
    guard let name = username else { return }
    let current = generation
    let summary = await ChessComImporting.importGames(sources, username: name, into: store)
    guard current == generation else { return }
    importSummary = summary
  }

  @discardableResult
  private func nextGeneration() -> Int {
    generation += 1
    return generation
  }

  private func forget() {
    phase = .loading
    profile = nil
    stats = nil
    games = []
    importSummary = nil
  }
}
