import ChessComLink
import ChessComPlay
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
  static func verify(
    username: String,
    client: ChessComClient
  ) async -> Result<ChessComProfile, ChessComFailure> {
    do {
      return .success(try await client.profile(username: username))
    } catch {
      return .failure(ChessComFailure(error))
    }
  }
}
