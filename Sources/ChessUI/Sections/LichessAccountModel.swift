import Foundation
import LichessLink
import LichessPlay
import Observation

/// Why a Lichess request failed.
public enum LichessFailure: Error, Equatable, Sendable {
  /// The token is wrong, expired, or revoked.
  case unauthorized, rateLimited, network
  /// Lichess answered 400: it refuses the seek or challenge.
  case notAllowed

  init(_ error: any Error) {
    switch error as? LichessError {
    case .unauthorized?: self = .unauthorized
    case .rateLimited?: self = .rateLimited
    case .http(status: 400)?: self = .notAllowed
    default: self = .network
    }
  }
}

/// Holds a token that is being verified, so the client can send it before it is saved.
private final class TokenSource: @unchecked Sendable {
  private let lock = NSLock()
  private var candidate: String?
  private let store: any TokenStore

  init(store: any TokenStore) { self.store = store }

  var token: String? { lock.withLock { candidate } ?? store.token() }
  func setCandidate(_ token: String?) { lock.withLock { candidate = token } }
}

/// The linked Lichess account: sign-in state, and the challenges and games from the event stream.
/// Lichess allows one event stream per token, so this model owns the only one.
@preconcurrency
@Observable
@MainActor
public final class LichessAccountModel {
  public enum Phase: Equatable {
    case signedOut, signingIn
    case signedIn(username: String)
    case failed(LichessFailure)
  }

  /// Wait before the first reconnect; it doubles up to `maxReconnectDelay`.
  static let firstReconnectDelay: Duration = .seconds(1)
  static let maxReconnectDelay: Duration = .seconds(30)
  /// Lichess asks clients to wait at least a minute after a 429.
  static let rateLimitDelay: Duration = .seconds(60)

  public private(set) var phase = Phase.signedOut
  private(set) var incomingChallenges: [LichessChallenge] = []
  public private(set) var ongoingGames: [LichessOngoingGame] = []
  /// The newest `gameStart` id. Changes on every start, so a screen can navigate on it.
  private(set) var startedGameID: String?
  /// The challenge the user sent and that nobody has answered yet.
  private(set) var outgoingChallengeID: String?
  /// The last challenge the user sent was declined. Cleared by the next send.
  private(set) var challengeWasDeclined = false
  /// A quick seek is open.
  private(set) var isSeeking = false
  /// Why the last seek, challenge, accept or decline failed. Cleared by the next one.
  private(set) var lobbyFailure: LichessFailure?

  @ObservationIgnored
  private let client: LichessClient
  @ObservationIgnored
  private let store: any TokenStore
  @ObservationIgnored
  private let source: TokenSource
  @ObservationIgnored
  private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored
  private var streamTask: Task<Void, Never>?
  @ObservationIgnored
  private var seekTask: Task<Void, Never>?

  /// - Parameter makeClient: builds the client around the token provider that the model hands it.
  /// - Parameter sleep: the pause between reconnects; tests replace it.
  init(
    store: any TokenStore,
    makeClient: (@escaping @Sendable () async -> String?) -> LichessClient,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    let source = TokenSource(store: store)
    self.store = store
    self.source = source
    self.sleep = sleep
    client = makeClient { source.token }
  }

  /// Verifies the stored token, if any, and opens the event stream.
  public func start() async {
    guard streamTask == nil, store.token() != nil else { return }
    phase = .signingIn
    await verifyAndOpenStream()
  }

  /// Verifies `token`, saves it, and opens the event stream.
  func signIn(token: String) async {
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      phase = .failed(.unauthorized)
      return
    }
    stopStream()
    phase = .signingIn
    source.setCandidate(token)
    defer { source.setCandidate(nil) }
    do {
      let account = try await client.account()
      try store.save(token)
      source.setCandidate(nil)
      phase = .signedIn(username: account.username)
      openStream()
    } catch {
      phase = .failed(LichessFailure(error))
    }
  }

  /// Revokes the token on a best-effort basis, and forgets it either way.
  func signOut() async {
    stopStream()
    try? await client.revokeToken()
    forgetAccount()
  }

  /// Reloads the ongoing games.
  func refresh() async {
    guard case .signedIn = phase else { return }
    do {
      let games = try await client.ongoingGames()
      guard case .signedIn = phase else { return }
      ongoingGames = games
    } catch {
      handle(error)
    }
  }

  // MARK: - Lobby

  /// Opens a seek and keeps it open until it is matched, fails, or `cancelSeek()` is called.
  /// The match arrives as `gameStart` on the event stream.
  public func seek(rated: Bool, minutes: Int, increment: Int) {
    guard !isSeeking, case .signedIn = phase else { return }
    lobbyFailure = nil
    isSeeking = true
    let client = client
    let task = Task { [weak self] in
      do {
        for try await _ in await client.seek(rated: rated, minutes: minutes, increment: increment) {
        }
        guard !Task.isCancelled else { return }
        self?.isSeeking = false
      } catch {
        guard !Task.isCancelled else { return }
        self?.isSeeking = false
        self?.fail(error)
      }
    }
    seekTask = task
  }

  /// Cancels the task that reads the seek stream, which closes the seek.
  func cancelSeek() {
    seekTask?.cancel()
    seekTask = nil
    isSeeking = false
  }

  /// Challenges `username`. The challenge stays in `outgoingChallengeID` until it is answered.
  public func challenge(
    username: String,
    rated: Bool,
    limitSeconds: Int,
    increment: Int,
    color: LichessChallengeColor
  ) async {
    guard outgoingChallengeID == nil, case .signedIn = phase else { return }
    lobbyFailure = nil
    challengeWasDeclined = false
    do {
      let challenge = try await client.challenge(
        username: username,
        rated: rated,
        limitSeconds: limitSeconds,
        increment: increment,
        color: color
      )
      outgoingChallengeID = challenge.id
    } catch {
      fail(error)
    }
  }

  /// Withdraws the challenge the user sent.
  public func cancelChallenge() async {
    guard let id = outgoingChallengeID else { return }
    outgoingChallengeID = nil
    do { try await client.cancelChallenge(id: id) } catch { fail(error) }
  }

  /// Accepts an incoming challenge; `gameStart` follows on the event stream.
  public func accept(challengeID id: String) async {
    lobbyFailure = nil
    do {
      try await client.acceptChallenge(id: id)
      incomingChallenges.removeAll { $0.id == id }
    } catch {
      fail(error)
    }
  }

  public func decline(challengeID id: String) async {
    lobbyFailure = nil
    do {
      try await client.declineChallenge(id: id)
      incomingChallenges.removeAll { $0.id == id }
    } catch {
      fail(error)
    }
  }

  private func fail(_ error: any Error) {
    if !handle(error) { lobbyFailure = LichessFailure(error) }
  }

  /// One game's connection, for the signed-in user. Lichess ids are the lowercased usernames.
  func gameConnection(id: String) -> LichessGameConnection {
    var userID = ""
    if case .signedIn(let username) = phase { userID = username.lowercased() }
    return LichessGameConnection(client: client, gameID: id, userID: userID)
  }

  // MARK: - Session

  private func verifyAndOpenStream() async {
    do {
      let account = try await client.account()
      phase = .signedIn(username: account.username)
      openStream()
    } catch {
      if !handle(error) { phase = .failed(LichessFailure(error)) }
    }
  }

  /// A 401 means the token is dead: sign out locally. Returns whether it did.
  @discardableResult
  private func handle(_ error: any Error) -> Bool {
    guard error as? LichessError == .unauthorized else { return false }
    stopStream()
    forgetAccount()
    return true
  }

  private func forgetAccount() {
    try? store.delete()
    cancelSeek()
    outgoingChallengeID = nil
    challengeWasDeclined = false
    lobbyFailure = nil
    incomingChallenges = []
    ongoingGames = []
    startedGameID = nil
    phase = .signedOut
  }

  // MARK: - Event stream

  private func openStream() {
    streamTask = Task { [weak self] in await self?.runStream() }
  }

  private func stopStream() {
    streamTask?.cancel()
    streamTask = nil
  }

  /// Reads events until cancelled, reconnecting with back-off after every disconnect.
  private func runStream() async {
    var delay = Self.firstReconnectDelay
    while !Task.isCancelled {
      do {
        // Events only report changes, so reload what a disconnect may have hidden.
        await refresh()
        for try await event in await client.eventStream() {
          if Task.isCancelled { return }
          delay = Self.firstReconnectDelay
          await apply(event)
        }
      } catch LichessError.unauthorized {
        handle(LichessError.unauthorized)
        return
      } catch LichessError.rateLimited {
        delay = max(delay, Self.rateLimitDelay)
      } catch {}
      guard !Task.isCancelled else { return }
      do { try await sleep(delay) } catch { return }
      delay = min(delay * 2, Self.maxReconnectDelay)
    }
  }

  private func apply(_ event: LichessEvent) async {
    switch event {
    case .challenge(let challenge):
      // Challenges the user sent arrive too; only incoming ones are for the user to answer.
      // Lichess user ids are the lowercased usernames.
      guard challenge.direction != .outgoing, !isSignedInUser(challenge.challenger.id) else {
        return
      }
      incomingChallenges.removeAll { $0.id == challenge.id }
      incomingChallenges.append(challenge)
    case .challengeCanceled(let challenge):
      incomingChallenges.removeAll { $0.id == challenge.id }
      if challenge.id == outgoingChallengeID { outgoingChallengeID = nil }
    case .challengeDeclined(let challenge):
      incomingChallenges.removeAll { $0.id == challenge.id }
      if challenge.id == outgoingChallengeID {
        outgoingChallengeID = nil
        challengeWasDeclined = true
      }
    case .gameStart(let game):
      startedGameID = game.gameId
      // A game has begun, so the seek or challenge that led to it is over.
      cancelSeek()
      outgoingChallengeID = nil
      await refresh()
    case .gameFinish:
      await refresh()
    }
  }

  private func isSignedInUser(_ id: String) -> Bool {
    guard case .signedIn(let username) = phase else { return false }
    return username.lowercased() == id.lowercased()
  }
}
