import Foundation
import HTTPSupportTests
import LichessLink
import Testing
@testable import ChessUI
@testable import LichessPlay

private let accountJSON = Data(#"{"id":"georges","username":"Georges"}"#.utf8)
private let playingJSON = Data(
  (#"{"nowPlaying":[{"gameId":"rCRw1Auv","color":"black","fen":"8/8/8/8/8/8/8/K6k w - - 0 60","#
    + #""opponent":{"id":"philippe","username":"Philippe","rating":1790},"isMyTurn":true}]}"#).utf8
)

private func challengeLine(
  type: String = "challenge",
  id: String,
  direction: String = "in"
) -> String {
  #"{"type":"\#(type)","challenge":{"id":"\#(id)","status":"created","#
    + #""challenger":{"id":"philippe","name":"Philippe"},"#
    + #""rated":false,"speed":"blitz","timeControl":{"type":"clock","limit":300,"increment":3},"#
    + #""color":"white","direction":"\#(direction)"}}"#
}

/// Accepts the token `good`; any other answers 401.
private func lichessAPI(_ request: URLRequest) -> (Int, Data) {
  guard request.value(forHTTPHeaderField: "Authorization") == "Bearer good" else {
    return (401, Data())
  }
  switch request.url!.path() {
  case "/api/account": return (200, accountJSON)
  case "/api/account/playing": return (200, playingJSON)
  default: return (200, Data("{}".utf8))
  }
}

private let outgoingChallengeJSON = Data(
  (#"{"id":"chal1234","status":"created","challenger":{"id":"georges","name":"Georges"},"#
    + #""destUser":{"id":"philippe","name":"Philippe"},"rated":false,"speed":"blitz","#
    + #""timeControl":{"type":"clock","limit":180,"increment":2},"#
    + #""color":"random","direction":"out"}"#).utf8
)

private func challengeAPI(_ request: URLRequest) -> (Int, Data) {
  request.url!.path() == "/api/challenge/Philippe"
    ? (200, outgoingChallengeJSON) : lichessAPI(request)
}

/// A transport that answers through `handler` and keeps every stream open for `push(_:to:)`.
private func makeTransport(
  _ handler: @escaping @Sendable (URLRequest) -> (Int, Data)
) -> FakeTransport {
  FakeTransport(keepStreamsOpen: true) { request in
    let (status, body) = handler(request)
    return (status, [:], body)
  }
}

extension FakeTransport {
  func pushEvent(_ line: String) {
    push(line, to: "/api/stream/event")
  }
}

@MainActor
struct LichessAccountModelTests {
  private let configuration = LichessConfiguration(
    baseURL: URL(string: "https://lichess.example.test")!,
    userAgent: "KingsideTests/1.0 (+tests)",
    clientID: "kingside-tests",
    redirectURI: URL(string: "kingside://oauth")!
  )

  private func makeModel(
    token: String? = nil,
    handler: @escaping @Sendable (URLRequest) -> (Int, Data) = lichessAPI
  ) -> (LichessAccountModel, InMemoryTokenStore, FakeTransport) {
    let store = InMemoryTokenStore(token: token)
    let transport = makeTransport(handler)
    let configuration = configuration
    // No real pause between reconnects.
    let model = LichessAccountModel(
      store: store,
      makeClient: {
        LichessClient(configuration: configuration, transport: transport, tokenProvider: $0)
      },
      sleep: { _ in await Task.yield() }
    )
    return (model, store, transport)
  }

  /// Yields until `condition` holds; the test's time limit cancels it.
  private func wait(until condition: () async -> Bool) async throws {
    while !(await condition()) {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func signInWithValidTokenSavesItAndOpensTheStream() async throws {
    let (model, store, transport) = makeModel()
    await model.signIn(token: " good\n")
    #expect(model.phase == .signedIn(username: "Georges"))
    #expect(store.token() == "good")
    try await transport.waitForRequest("GET /api/stream/event")
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func signInWithRejectedTokenSavesNothing() async {
    let (model, store, _) = makeModel()
    await model.signIn(token: "bad")
    #expect(model.phase == .failed(.unauthorized))
    #expect(store.token() == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func startWithStoredTokenSignsInAndLoadsOngoingGames() async throws {
    let (model, _, transport) = makeModel(token: "good")
    await model.start()
    #expect(model.phase == .signedIn(username: "Georges"))
    try await wait { model.ongoingGames.count == 1 }
    #expect(model.ongoingGames.first?.gameId == "rCRw1Auv")
    try await transport.waitForRequest("GET /api/stream/event")
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func startWithoutTokenMakesNoRequest() async {
    let (model, _, transport) = makeModel()
    await model.start()
    #expect(model.phase == .signedOut)
    #expect(await transport.paths.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func startWithRevokedTokenDeletesIt() async {
    let (model, store, _) = makeModel(token: "revoked")
    await model.start()
    #expect(model.phase == .signedOut)
    #expect(store.token() == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func signOutRevokesThenDeletesTheToken() async throws {
    let (model, store, transport) = makeModel(token: "good")
    await model.start()
    try await transport.waitForRequest("GET /api/stream/event")
    await model.signOut()
    #expect(model.phase == .signedOut)
    #expect(store.token() == nil)
    #expect(await transport.paths.contains("DELETE /api/token"))
    // The revoke request still carried the token.
    let revoke = try #require(await transport.requests.last)
    #expect(revoke.value(forHTTPHeaderField: "Authorization") == "Bearer good")
  }

  @Test(.timeLimit(.minutes(1)))
  func signOutIgnoresRevokeFailure() async {
    let (model, store, _) = makeModel(token: "good") { request in
      request.httpMethod == "DELETE" ? (500, Data()) : lichessAPI(request)
    }
    await model.start()
    await model.signOut()
    #expect(model.phase == .signedOut)
    #expect(store.token() == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func eventsAddAndRemoveChallengesAndReportStartedGames() async throws {
    let (model, _, transport) = makeModel(token: "good")
    await model.start()
    try await transport.waitForRequest("GET /api/stream/event")
    await transport.pushEvent(challengeLine(id: "c1"))
    try await wait { model.incomingChallenges.count == 1 }
    await transport.pushEvent(challengeLine(id: "c2"))
    await transport.pushEvent(challengeLine(id: "c3", direction: "out"))
    // The user's own challenge without `direction` is outgoing too; events arrive in order,
    // so the empty list below also shows that it was dropped.
    await transport.pushEvent(
      challengeLine(id: "c4", direction: "out")
        .replacing(#""direction":"out""#, with: #""x":0"#)
        .replacing(#""id":"philippe","name":"Philippe""#, with: #""id":"georges","name":"Georges""#)
    )
    try await wait { model.incomingChallenges.count == 2 }
    await transport.pushEvent(challengeLine(type: "challengeCanceled", id: "c1"))
    await transport.pushEvent(challengeLine(type: "challengeDeclined", id: "c2"))
    try await wait { model.incomingChallenges.isEmpty }

    await transport.pushEvent(
      #"{"type":"gameStart","game":{"gameId":"abcd1234","#
        + #""color":"white","fen":"x","isMyTurn":true}}"#
    )
    try await wait { model.startedGameID == "abcd1234" }
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func unauthorizedOnTheStreamSignsOut() async throws {
    let (model, store, _) = makeModel(token: "good") { request in
      request.url!.path() == "/api/stream/event" ? (401, Data()) : lichessAPI(request)
    }
    await model.start()
    try await wait { model.phase == .signedOut }
    #expect(store.token() == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func streamReconnectsAfterADisconnectAndWaitsAMinuteAfterRateLimit() async throws {
    let waits = Waits()
    let store = InMemoryTokenStore(token: "good")
    let transport = makeTransport { request in
      request.url!.path() == "/api/stream/event" ? (429, Data()) : lichessAPI(request)
    }
    let configuration = configuration
    let model = LichessAccountModel(
      store: store,
      makeClient: {
        LichessClient(configuration: configuration, transport: transport, tokenProvider: $0)
      },
      sleep: { duration in
        waits.record(duration)
        await Task.yield()
      }
    )
    await model.start()
    try await wait { waits.all.count >= 2 }
    await model.signOut()
    #expect(waits.all.allSatisfy { $0 >= .seconds(60) })
  }

  // MARK: - Lobby

  /// A model that is signed in with its event stream open.
  private func signedInModel(
    handler: @escaping @Sendable (URLRequest) -> (Int, Data) = lichessAPI
  ) async throws -> (LichessAccountModel, FakeTransport) {
    let (model, _, transport) = makeModel(token: "good", handler: handler)
    await model.start()
    try await transport.waitForRequest("GET /api/stream/event")
    return (model, transport)
  }

  @Test(.timeLimit(.minutes(1)))
  func seekSendsTheRequestAndKeepsWaiting() async throws {
    let (model, transport) = try await signedInModel()
    model.seek(rated: true, minutes: 10, increment: 5)
    #expect(model.isSeeking)
    try await transport.waitForRequest("POST /api/board/seek")
    let request = try #require(
      await transport.requests.first { $0.url!.path() == "/api/board/seek" }
    )
    #expect(
      String(bytes: request.httpBody ?? Data(), encoding: .utf8)
        == "rated=true&time=10&increment=5"
    )
    #expect(model.isSeeking)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellingTheSeekClosesTheStream() async throws {
    let (model, transport) = try await signedInModel()
    model.seek(rated: false, minutes: 10, increment: 0)
    try await transport.waitForRequest("POST /api/board/seek")
    model.cancelSeek()
    #expect(!model.isSeeking)
    try await transport.waitForStreamTermination("/api/board/seek")
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func theSeekStreamEndingEndsTheWaitingState() async throws {
    let (model, transport) = try await signedInModel()
    model.seek(rated: false, minutes: 15, increment: 10)
    try await transport.waitForRequest("POST /api/board/seek")
    await transport.finishStream("/api/board/seek")
    try await wait { !model.isSeeking }
    #expect(model.lobbyFailure == nil)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func aRefusedSeekShowsNotAllowed() async throws {
    let (model, _) = try await signedInModel { request in
      request.url!.path() == "/api/board/seek" ? (400, Data()) : lichessAPI(request)
    }
    model.seek(rated: true, minutes: 3, increment: 0)
    try await wait { !model.isSeeking }
    #expect(model.lobbyFailure == .notAllowed)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func aGameStartEndsTheSeekAndRefreshesTheGames() async throws {
    let (model, transport) = try await signedInModel()
    model.seek(rated: false, minutes: 10, increment: 0)
    try await transport.waitForRequest("POST /api/board/seek")
    let before = await transport.paths.count { $0 == "GET /api/account/playing" }
    await transport.pushEvent(
      #"{"type":"gameStart","game":{"gameId":"abcd1234","#
        + #""color":"white","fen":"x","isMyTurn":true}}"#
    )
    try await wait { model.startedGameID == "abcd1234" }
    #expect(!model.isSeeking)
    try await wait { await transport.paths.count { $0 == "GET /api/account/playing" } > before }
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func challengeIsSentAndTrackedUntilItIsCancelled() async throws {
    let (model, transport) = try await signedInModel(handler: challengeAPI)
    await model.challenge(
      username: "Philippe",
      rated: true,
      limitSeconds: 180,
      increment: 2,
      color: .black
    )
    #expect(model.outgoingChallengeID == "chal1234")
    let request = try #require(
      await transport.requests.first { $0.url!.path() == "/api/challenge/Philippe" }
    )
    #expect(
      String(bytes: request.httpBody ?? Data(), encoding: .utf8)
        == "rated=true&clock.limit=180&clock.increment=2&color=black"
    )

    await model.cancelChallenge()
    #expect(model.outgoingChallengeID == nil)
    #expect(!model.challengeWasDeclined)
    #expect(await transport.paths.contains("POST /api/challenge/chal1234/cancel"))
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func aDeclinedChallengeClearsTheTrackingAndShowsDeclined() async throws {
    let (model, transport) = try await signedInModel(handler: challengeAPI)
    await model.challenge(
      username: "Philippe",
      rated: false,
      limitSeconds: 180,
      increment: 2,
      color: .random
    )
    await transport.pushEvent(
      challengeLine(type: "challengeDeclined", id: "other", direction: "out")
    )
    await transport.pushEvent(
      challengeLine(type: "challengeDeclined", id: "chal1234", direction: "out")
    )
    try await wait { model.challengeWasDeclined }
    #expect(model.outgoingChallengeID == nil)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func aGameStartClearsTheOutgoingChallenge() async throws {
    let (model, transport) = try await signedInModel(handler: challengeAPI)
    await model.challenge(
      username: "Philippe",
      rated: false,
      limitSeconds: 180,
      increment: 2,
      color: .random
    )
    await transport.pushEvent(
      #"{"type":"gameStart","game":{"gameId":"chal1234","#
        + #""color":"white","fen":"x","isMyTurn":true}}"#
    )
    try await wait { model.startedGameID == "chal1234" }
    #expect(model.outgoingChallengeID == nil)
    #expect(!model.challengeWasDeclined)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func acceptAndDeclineHitTheirPathsAndDropTheChallenge() async throws {
    let (model, transport) = try await signedInModel()
    await transport.pushEvent(challengeLine(id: "c1"))
    await transport.pushEvent(challengeLine(id: "c2"))
    try await wait { model.incomingChallenges.count == 2 }
    await model.accept(challengeID: "c1")
    await model.decline(challengeID: "c2")
    #expect(await transport.paths.contains("POST /api/challenge/c1/accept"))
    #expect(await transport.paths.contains("POST /api/challenge/c2/decline"))
    #expect(model.incomingChallenges.isEmpty)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func aFailedAcceptKeepsTheChallengeAndShowsTheFailure() async throws {
    let (model, transport) = try await signedInModel { request in
      request.url!.path() == "/api/challenge/c1/accept" ? (429, Data()) : lichessAPI(request)
    }
    await transport.pushEvent(challengeLine(id: "c1"))
    try await wait { model.incomingChallenges.count == 1 }
    await model.accept(challengeID: "c1")
    #expect(model.lobbyFailure == .rateLimited)
    #expect(model.incomingChallenges.count == 1)
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func gameFinishRefreshesTheOngoingGames() async throws {
    let (model, transport) = try await signedInModel()
    try await wait { model.ongoingGames.count == 1 }
    let before = await transport.paths.count { $0 == "GET /api/account/playing" }
    await transport.pushEvent(#"{"type":"gameFinish","game":{"gameId":"rCRw1Auv"}}"#)
    try await wait { await transport.paths.count { $0 == "GET /api/account/playing" } > before }
    await model.signOut()
  }

  @Test
  func failuresMapToTheirCauses() {
    #expect(LichessFailure(LichessError.http(status: 400)) == .notAllowed)
    #expect(LichessFailure(LichessError.http(status: 500)) == .network)
    #expect(LichessFailure(LichessError.rateLimited) == .rateLimited)
    #expect(LichessFailure(URLError(.notConnectedToInternet)) == .network)
  }

  @Test(.timeLimit(.minutes(1)))
  func signedInModelGivesAnAuthorizedConnectionForTheGameAndLowercasedUsername() async throws {
    let (model, _, transport) = makeModel()
    await model.signIn(token: "good")
    try await transport.waitForRequest("GET /api/stream/event")
    let connection = model.gameConnection(id: "rCRw1Auv")
    #expect(connection.userID == "georges")
    try await connection.send(.resign)
    #expect(await transport.paths.last == "POST /api/board/game/rCRw1Auv/resign")
    await model.signOut()
  }

  @Test(.timeLimit(.minutes(1)))
  func signedOutModelGivesAConnectionThatMatchesNoPlayer() {
    let (model, _, _) = makeModel()
    #expect(model.gameConnection(id: "rCRw1Auv").userID.isEmpty)
  }
}

private final class Waits: @unchecked Sendable {
  private let lock = NSLock()
  private var durations: [Duration] = []

  var all: [Duration] { lock.withLock { durations } }
  func record(_ duration: Duration) { lock.withLock { durations.append(duration) } }
}
