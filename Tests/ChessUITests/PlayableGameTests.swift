import ChessContent
import ChessCore
import Foundation
import Testing
@testable import ChessPlay
@testable import ChessUI

/// A connection whose events the test pushes; records every action sent.
private final class FakeOnlineConnection: OnlineGameConnection, @unchecked Sendable {
  let service = "lichess"
  private let lock = NSLock()
  private var continuation: AsyncThrowingStream<OnlineGameEvent, Error>.Continuation?
  private var sentActions: [OnlineAction] = []

  var sent: [OnlineAction] { lock.withLock { sentActions } }

  func events() -> AsyncThrowingStream<OnlineGameEvent, Error> {
    let (stream, continuation) = AsyncThrowingStream<OnlineGameEvent, Error>.makeStream()
    lock.withLock { self.continuation = continuation }
    return stream
  }

  func push(_ event: OnlineGameEvent) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(event)
  }

  func send(_ action: OnlineAction) throws { lock.withLock { sentActions.append(action) } }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
final class PlayableGameTests {
  private let suiteName = "ChessUITests.\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory.appending(
    path: "ChessUITests-\(UUID().uuidString)"
  )
  private let connection = FakeOnlineConnection()

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeLocal() throws -> GameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let storage = AppModel.Storage(
      defaults: defaults,
      gamesFileURL: directory.appending(path: GamePersistenceStore.fileName),
      playsFeedback: false
    )
    let model = AppModel(catalog: try ContentCatalog.load(), storage: storage)
    return model.makeGameSession(
      .new(
        GameSetup(
          mode: .passAndPlay,
          white: PlayerInfo(name: "A"),
          black: PlayerInfo(name: "B"),
          timeControl: .untimed
        )
      )
    )
  }

  private func makeOnline() throws -> OnlineGameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let session = OnlineGameSession(
      connection: connection,
      catalog: try ContentCatalog.load(),
      localization: Localization(preferredLanguages: ["en-US"]),
      settings: SettingsStore(defaults: defaults),
      store: GamePersistenceStore(fileURL: directory.appending(path: GamePersistenceStore.fileName))
    )
    session.activate()
    return session
  }

  private func start(state: OnlineGameState = OnlineGameState()) -> OnlineGameStart {
    OnlineGameStart(
      gameID: "abcd1234",
      white: OnlinePlayer(name: "Alice", rating: 1500),
      black: OnlinePlayer(name: "Bob", rating: 1600),
      myColor: .white,
      timeControl: nil,
      rated: true,
      state: state
    )
  }

  private func until(_ condition: () -> Bool) async throws {
    while !condition() {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  @Test
  func localGameSupportsEverything() throws {
    let game: any PlayableGame = try makeLocal()
    #expect(game.supportsHint && game.supportsTakeback && game.supportsRematch)
    #expect(game.canOfferDraw)
    #expect(game.botMessage == nil)
  }

  @Test
  func onlineGameHasNoHintTakebackOrRematch() async throws {
    let session = try makeOnline()
    connection.push(.started(start()))
    try await until { session.start != nil }
    let game: any PlayableGame = session
    #expect(!game.supportsHint && !game.supportsTakeback && !game.supportsRematch)
    #expect(!game.canTakeback && !game.isLoadingHint)
    #expect(game.botMessage == nil)
    #expect(game.materialAdvantage == session.materialAdvantage)
    #expect(game.canOfferDraw)
  }

  @Test
  func onlineOfferDrawWaitsForTheOpponentsAnswer() async throws {
    let session = try makeOnline()
    #expect(!session.canOfferDraw)
    connection.push(.started(start()))
    try await until { session.start != nil }
    session.apply(.offerDraw)
    #expect(!session.canOfferDraw)
    try await until { connection.sent.contains(.offerDraw) }
  }

  @Test
  func onlineResignGoesToTheServer() async throws {
    let session = try makeOnline()
    connection.push(.started(start()))
    try await until { session.start != nil }
    session.apply(.resign)
    try await until { connection.sent.contains(.resign) }
  }

  @Test
  func sendChatReachesTheConnection() async throws {
    let session = try makeOnline()
    connection.push(.started(start()))
    try await until { session.start != nil }
    session.sendChat("  hello  ")
    session.sendChat("   ")
    session.sendChat(String(repeating: "a", count: OnlineChat.maxLength + 20))
    try await until { connection.sent.count == 2 }
    #expect(
      connection.sent == [
        .chat("hello"), .chat(String(repeating: "a", count: OnlineChat.maxLength)),
      ]
    )
  }

  @Test
  func chatOffSendsNothingAndShowsNothing() async throws {
    let session = try makeOnline()
    connection.push(.started(start()))
    connection.push(.chat(OnlineChatLine(username: "Bob", text: "hi")))
    try await until { !session.chat.isEmpty }
    #expect(session.chatMessages.count == 1 && session.unreadChatCount == 1)
    session.markChatRead()
    #expect(session.unreadChatCount == 0)
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    var settings = AppSettings()
    settings.chatEnabled = false
    defaults.set(try JSONEncoder().encode(settings), forKey: SettingsStore.defaultsKey)
    let off = try makeOnline()
    off.sendChat("hi")
    #expect(!off.isChatEnabled && off.chatMessages.isEmpty)
    try await Task.sleep(for: .milliseconds(50))
    #expect(connection.sent.isEmpty)
  }

  @Test
  func mutingTheOpponentHidesTheirLinesForThisSession() async throws {
    let session = try makeOnline()
    connection.push(.started(start()))
    connection.push(.chat(OnlineChatLine(username: "Bob", text: "hi")))
    connection.push(.chat(OnlineChatLine(username: "Alice", text: "yo")))
    try await until { session.chat.count == 2 }
    #expect(session.opponentName == "Bob")
    session.setOpponentMuted(true)
    #expect(session.chatMessages.map(\.kind) == [.own])
    session.setOpponentMuted(false)
    #expect(session.chatMessages.map(\.kind) == [.opponent, .own])
  }

  #if !os(tvOS)
    @Test
    func menuTargetHidesWhatAnOnlineGameCannotDo() async throws {
      let session = try makeOnline()
      connection.push(.started(start()))
      try await until { session.start != nil }
      let online = GameMenuTarget(session: session) {}
      #expect(!online.showsHint && !online.showsTakeback && !online.showsRematch)
      #expect(online.canOfferDraw && online.canResign)
      #expect(!online.canHint && !online.canTakeback)

      let local = GameMenuTarget(session: try makeLocal()) {}
      #expect(local.showsHint && local.showsTakeback && local.showsRematch)
      // A puzzle has no game and keeps every item, dimmed.
      #expect(GameMenuTarget {}.showsHint)
    }
  #endif
}
