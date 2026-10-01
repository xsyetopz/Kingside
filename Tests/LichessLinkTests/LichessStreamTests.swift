import Foundation
import Testing
@testable import LichessLink

@Suite
struct LichessStreamTests {
  @Test
  func blankAndUnknownLinesAreSkipped() throws {
    #expect(try LichessEvent.parse(line: "") == nil)
    #expect(try LichessEvent.parse(line: "  \r") == nil)
    #expect(try LichessEvent.parse(line: #"{"type":"futureEvent","x":[1]}"#) == nil)
    #expect(try LichessEvent.parse(line: #"{"no":"type"}"#) == nil)
    #expect(try LichessGameEvent.parse(line: "\n") == nil)
    #expect(try LichessGameEvent.parse(line: #"{"type":"somethingNew"}"#) == nil)
  }

  @Test
  func malformedKnownEventThrowsDecodingError() {
    #expect(throws: LichessError.self) { try LichessEvent.parse(line: #"{"type":"gameStart"}"#) }
    #expect(throws: LichessError.self) { try LichessGameEvent.parse(line: "not json") }
  }

  private func stateStatus(_ name: String) throws -> LichessGameStatus? {
    let line =
      #"{"type":"gameState","moves":"","wtime":1,"btime":1,"winc":0,"binc":0,"status":"\#(name)"}"#
    guard case .gameState(let state)? = try LichessGameEvent.parse(line: line) else { return nil }
    return state.status
  }

  @Test(arguments: [
    ("created", LichessGameStatus.created), ("started", .started), ("aborted", .aborted),
    ("mate", .mate), ("resign", .resign), ("stalemate", .stalemate), ("timeout", .timeout),
    ("draw", .draw), ("outoftime", .outoftime), ("cheat", .cheat), ("noStart", .noStart),
    ("unknownFinish", .unknownFinish), ("variantEnd", .variantEnd),
  ])
  func knownGameStatusDecodesToItsCase(name: String, status: LichessGameStatus) throws {
    #expect(try stateStatus(name) == status)
  }

  @Test
  func unknownGameStatusDecodesToOther() throws {
    #expect(try stateStatus("newThing") == .other("newThing"))
  }

  private func decoded<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    try JSONDecoder().decode(type, from: Data(#""\#(name)""#.utf8))
  }

  @Test(arguments: [
    ("created", LichessChallengeStatus.created), ("offline", .offline),
    ("canceled", .canceled), ("declined", .declined), ("accepted", .accepted),
  ])
  func knownChallengeStatusDecodesToItsCase(name: String, status: LichessChallengeStatus) throws {
    #expect(try decoded(name, as: LichessChallengeStatus.self) == status)
  }

  @Test
  func unknownChallengeStatusDecodesToOther() throws {
    #expect(try decoded("expired", as: LichessChallengeStatus.self) == .other("expired"))
  }

  @Test
  func unknownChallengeDirectionDecodesToOther() throws {
    #expect(try decoded("sideways", as: LichessChallengeDirection.self) == .other("sideways"))
  }

  @Test
  func decodesEveryAccountEventType() throws {
    let events = try fixtureLines("events").compactMap { try LichessEvent.parse(line: $0) }
    #expect(events.count == 5)
    guard case .gameStart(let start) = events[0] else {
      Issue.record("expected gameStart")
      return
    }
    #expect(start.gameId == "rCRw1Auv")
    #expect(start.color == .black)
    #expect(start.fen?.hasPrefix("rnbqkbnr/pppppppp/8/8/4P3") == true)
    #expect(start.opponent?.username == "Philippe")
    #expect(start.opponent?.rating == 1790)
    #expect(start.isMyTurn == true)
    #expect(start.rated == true)
    #expect(start.speed == "blitz")
    #expect(start.secondsLeft == 300)
    guard case .gameFinish(let finish) = events[1] else {
      Issue.record("expected gameFinish")
      return
    }
    #expect(finish.winner == .white)
    #expect(finish.secondsLeft == nil)
    guard case .challenge(let challenge) = events[2] else {
      Issue.record("expected challenge")
      return
    }
    #expect(challenge.id == "VU0nyvsW")
    #expect(challenge.challenger.name == "Philippe")
    #expect(challenge.challenger.title == "FM")
    #expect(challenge.destUser?.rating == 1838)
    #expect(
      challenge.timeControl
        == LichessTimeControl(type: "clock", limit: 300, increment: 3, daysPerTurn: nil)
    )
    #expect(challenge.color == .white)
    #expect(challenge.direction == .incoming)
    guard case .challengeCanceled(let canceled) = events[3] else {
      Issue.record("expected challengeCanceled")
      return
    }
    #expect(canceled.status == .canceled)
    guard case .challengeDeclined(let declined) = events[4] else {
      Issue.record("expected challengeDeclined")
      return
    }
    #expect(declined.timeControl.type == "correspondence")
    #expect(declined.timeControl.daysPerTurn == 3)
    #expect(declined.color == .random)
  }

  @Test
  func decodesEveryGameEventType() throws {
    let events = try fixtureLines("game-stream").compactMap { try LichessGameEvent.parse(line: $0) }
    #expect(events.count == 7)
    guard case .gameFull(let full) = events[0] else {
      Issue.record("expected gameFull")
      return
    }
    #expect(full.id == "rCRw1Auv")
    #expect(full.white.name == "Georges")
    #expect(full.white.rating == 1838)
    #expect(full.black.title == "FM")
    #expect(full.initialFen == "startpos")
    #expect(full.clock == LichessGameClock(initial: 300_000, increment: 3000))
    #expect(full.rated)
    #expect(full.speed == "blitz")
    #expect(full.state.moves == "e2e4 e7e5")
    #expect(full.state.btime == 298_000)
    guard case .gameState(let state) = events[1] else {
      Issue.record("expected gameState")
      return
    }
    #expect(state.moves.split(separator: " ").count == 3)
    #expect(state.wtime == 297_000)
    #expect(state.bdraw == true)
    #expect(state.wdraw == nil)
    #expect(state.wtakeback == false)
    #expect(state.winner == nil)
    #expect(events[2] == .chatLine(username: "Philippe", text: "Good luck!", room: "player"))
    #expect(events[3] == .opponentGone(gone: true, claimWinInSeconds: 20))
    #expect(events[4] == .opponentGone(gone: false, claimWinInSeconds: nil))
    guard case .gameState(let last) = events[5] else {
      Issue.record("expected gameState")
      return
    }
    #expect(last.status == .resign)
    #expect(last.winner == .white)
    guard case .gameFull(let ai) = events[6] else {
      Issue.record("expected gameFull")
      return
    }
    #expect(ai.black.aiLevel == 3)
    #expect(ai.black.rating == nil)
    #expect(ai.initialFen.hasPrefix("rnbqkbnr"))
  }

  @Test
  func decodesAccountAndOngoingGames() async throws {
    let account = try fixtureData("account")
    let playing = try fixtureData("playing")
    let (client, _) = makeClient { request in
      (200, [:], request.url!.path == "/api/account" ? account : playing)
    }
    let a = try await client.account()
    #expect(a.id == "georges")
    #expect(a.username == "Georges")
    #expect(a.perfs?["blitz"]?.rating == 1838)
    let games = try await client.ongoingGames()
    #expect(games.count == 2)
    #expect(games[0].gameId == "rCRw1Auv")
    #expect(games[0].color == .black)
    #expect(games[0].isMyTurn)
    #expect(games[0].secondsLeft == 300)
    #expect(games[0].opponent.username == "Philippe")
    #expect(games[1].opponent.id == nil)
    #expect(games[1].opponent.ai == 3)
  }

  @Test
  func eventStreamYieldsDecodedEventsAndSkipsNoise() async throws {
    let (client, transport) = makeClient(streamLines: try fixtureLines("events")) { _ in
      (200, [:], Data())
    }
    var count = 0
    for try await _ in await client.eventStream() { count += 1 }
    #expect(count == 5)
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/stream/event")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/x-ndjson")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
  }

  @Test
  func gameStreamYieldsEvents() async throws {
    let (client, transport) = makeClient(streamLines: try fixtureLines("game-stream")) { _ in
      (200, [:], Data())
    }
    var count = 0
    for try await _ in try await client.gameStream(id: "rCRw1Auv") { count += 1 }
    #expect(count == 7)
    #expect(await transport.requests.first?.url?.path == "/api/board/game/stream/rCRw1Auv")
  }

  @Test
  func streamMapsErrorStatus() async throws {
    let (client, _) = makeClient { _ in (401, [:], Data()) }
    await #expect(throws: LichessError.unauthorized) {
      for try await _ in await client.eventStream() {}
    }
  }

  @Test
  func streamRateLimitStartsTheBackoff() async throws {
    let clock = TestClock()
    let limited = LockedFlag(true)
    let (client, transport) = makeClient(clock: clock) { _ in
      limited.value ? (429, [:], Data()) : (200, [:], Data("{\"ok\":true}".utf8))
    }
    await #expect(throws: LichessError.rateLimited) {
      for try await _ in await client.eventStream() {}
    }
    limited.value = false
    clock.advance(59)
    await #expect(throws: LichessError.rateLimited) { try await client.resign(gameID: "abc12345") }
    #expect(await transport.requests.count == 1)
  }

  @Test
  func cancellingSeekTerminatesTheConnection() async throws {
    let (client, transport) = makeClient(streamLines: ["", ""], keepStreamOpen: true) { _ in
      (200, [:], Data())
    }
    let consumer = Task {
      for try await _ in await client.seek(rated: true, minutes: 5, increment: 3) {}
    }
    while await transport.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    consumer.cancel()
    for _ in 0..<200 where !(await transport.streamTerminated) {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.streamTerminated)
  }
}
