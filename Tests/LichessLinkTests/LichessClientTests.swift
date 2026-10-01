import Foundation
import Testing
@testable import LichessLink

private func bodyString(_ request: URLRequest) -> String {
  String(bytes: request.httpBody ?? Data(), encoding: .utf8) ?? ""
}

@Suite
struct LichessClientTests {
  @Test
  func moveRequestShape() async throws {
    let (client, transport) = makeClient()
    try await client.move(gameID: "rCRw1Auv", uci: "e7e8q")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(
      request.url?.absoluteString
        == "https://lichess.example.test/api/board/game/rCRw1Auv/move/e7e8q"
    )
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == testConfiguration.userAgent)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.httpBody == nil)
  }

  @Test
  func noTokenMeansNoAuthorizationHeader() async throws {
    let (client, transport) = makeClient(token: nil)
    try await client.resign(gameID: "rCRw1Auv")
    #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test
  func seekSendsFormBody() async throws {
    let (client, transport) = makeClient { _ in (200, [:], Data()) }
    for try await _ in await client.seek(rated: false, minutes: 10, increment: 5) {}
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/board/seek")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
    )
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/x-ndjson")
    #expect(bodyString(request) == "rated=false&time=10&increment=5")
  }

  @Test
  func gameActionPaths() async throws {
    let (client, transport) = makeClient()
    try await client.resign(gameID: "abc12345")
    try await client.abort(gameID: "abc12345")
    try await client.claimVictory(gameID: "abc12345")
    try await client.draw(gameID: "abc12345", accept: true)
    try await client.draw(gameID: "abc12345", accept: false)
    try await client.acceptChallenge(id: "VU0nyvsW")
    try await client.declineChallenge(id: "VU0nyvsW")
    try await client.cancelChallenge(id: "VU0nyvsW")
    let requests = await transport.requests
    #expect(
      requests.map { $0.url!.path } == [
        "/api/board/game/abc12345/resign", "/api/board/game/abc12345/abort",
        "/api/board/game/abc12345/claim-victory", "/api/board/game/abc12345/draw/yes",
        "/api/board/game/abc12345/draw/no",
        "/api/challenge/VU0nyvsW/accept", "/api/challenge/VU0nyvsW/decline",
        "/api/challenge/VU0nyvsW/cancel",
      ]
    )
    #expect(requests.allSatisfy { $0.httpMethod == "POST" })
  }

  @Test
  func chatEscapesFormText() async throws {
    let (client, transport) = makeClient()
    try await client.chat(gameID: "abc12345", text: "a&b=c d+é")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/board/game/abc12345/chat")
    #expect(bodyString(request) == "room=player&text=a%26b%3Dc%20d%2B%C3%A9")
  }

  @Test
  func challengeRequestAndResponse() async throws {
    let challenge = try fixtureData("challenge")
    let (client, transport) = makeClient { _ in (200, [:], challenge) }
    let result = try await client.challenge(
      username: "Philippe_1",
      rated: true,
      limitSeconds: 300,
      increment: 3,
      color: .random
    )
    #expect(result.id == "VU0nyvsW")
    #expect(result.direction == "out")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/challenge/Philippe_1")
    #expect(bodyString(request) == "rated=true&clock.limit=300&clock.increment=3&color=random")
  }

  @Test
  func challengeAIReturnsGameID() async throws {
    let (client, transport) = makeClient { _ in
      (201, [:], Data(#"{"id":"aiGame01","rated":false}"#.utf8))
    }
    let id = try await client.challengeAI(level: 3, limitSeconds: 600, increment: 0, color: .white)
    #expect(id == "aiGame01")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/challenge/ai")
    #expect(bodyString(request) == "level=3&clock.limit=600&clock.increment=0&color=white")
  }

  @Test
  func revokeTokenIsDelete() async throws {
    let (client, transport) = makeClient()
    try await client.revokeToken()
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path == "/api/token")
  }

  @Test
  func requestsAreSerialized() async throws {
    let (client, transport) = makeClient()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<5 { group.addTask { try await client.resign(gameID: "abc12345") } }
      try await group.waitForAll()
    }
    #expect(await transport.requests.count == 5)
    #expect(await transport.maxConcurrency == 1)
  }

  @Test
  func unauthorizedMapsTo401Error() async throws {
    let (client, _) = makeClient { _ in (401, [:], Data()) }
    await #expect(throws: LichessError.unauthorized) { try await client.account() }
  }

  @Test
  func otherStatusesAndBadBodies() async throws {
    let (client, _) = makeClient { request in
      request.url!.path == "/api/account" ? (503, [:], Data()) : (200, [:], Data("nope".utf8))
    }
    await #expect(throws: LichessError.http(status: 503)) { try await client.account() }
    await #expect(throws: LichessError.self) { try await client.ongoingGames() }
  }

  @Test
  func rateLimitBacksOffForSixtySeconds() async throws {
    let clock = TestClock()
    let limited = LockedFlag(true)
    let (client, transport) = makeClient(clock: clock) { _ in
      limited.value ? (429, [:], Data()) : (200, [:], Data("{\"ok\":true}".utf8))
    }
    await #expect(throws: LichessError.rateLimited) { try await client.resign(gameID: "abc12345") }
    limited.value = false
    clock.advance(59)
    await #expect(throws: LichessError.rateLimited) { try await client.resign(gameID: "abc12345") }
    await #expect(throws: LichessError.rateLimited) {
      for try await _ in await client.eventStream() {}
    }
    #expect(await transport.requests.count == 1)
    clock.advance(1)
    try await client.resign(gameID: "abc12345")
    #expect(await transport.requests.count == 2)
  }

  @Test(arguments: ["", "a/b", "../x", "abc 123", "abc?x=1", "é1234567", "abc%2F"])
  func badIDsMakeNoRequest(_ id: String) async throws {
    let (client, transport) = makeClient()
    await #expect(throws: LichessError.self) { try await client.resign(gameID: id) }
    await #expect(throws: LichessError.self) { try await client.move(gameID: id, uci: "e2e4") }
    await #expect(throws: LichessError.self) { try await client.acceptChallenge(id: id) }
    await #expect(throws: LichessError.self) { try await client.chat(gameID: id, text: "hi") }
    await #expect(throws: LichessError.self) { _ = try await client.gameStream(id: id) }
    #expect(await transport.requests.isEmpty)
  }

  @Test(arguments: [
    "", "e2", "e2e", "e2e4x", "i2e4", "e9e4", "E2E4", "e2e4qq", "e2e4/", "e7e8k", "e2e4 ",
    "../e2e4",
  ])
  func badUCIMakesNoRequest(_ uci: String) async throws {
    let (client, transport) = makeClient()
    await #expect(throws: LichessError.self) { try await client.move(gameID: "abc12345", uci: uci) }
    #expect(await transport.requests.isEmpty)
  }

  @Test(arguments: [
    "", "a", "../admin", "a/b", "user?x=1", "has space", "üñíçode",
    String(repeating: "a", count: 31),
  ])
  func badUsernameMakesNoRequest(_ name: String) async throws {
    let (client, transport) = makeClient()
    await #expect(throws: LichessError.self) {
      _ = try await client.challenge(
        username: name,
        rated: false,
        limitSeconds: 60,
        increment: 0,
        color: .white
      )
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func badAILevelMakesNoRequest() async throws {
    let (client, transport) = makeClient()
    await #expect(throws: LichessError.self) {
      _ = try await client.challengeAI(level: 9, limitSeconds: 60, increment: 0, color: .white)
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func validUCIsAreAccepted() {
    for uci in ["e2e4", "a7a8q", "h2h1n", "b7b8r", "c7c8b"] {
      #expect(LichessClient.isValidUCI(uci))
    }
  }
}

/// A thread-safe flag the `@Sendable` fake-transport handler can read while the test mutates it.
final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Bool
  init(_ value: Bool) { stored = value }
  var value: Bool {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
