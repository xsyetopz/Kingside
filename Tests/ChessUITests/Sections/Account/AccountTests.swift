import ChessComLink
import ChessContent
import ChessOnline
import ChessPlay
import Foundation
import HTTPSupportTests
import Testing
@testable import ChessComPlay
@testable import ChessUI

private let baseURL = URL(string: "https://pub.example.test/pub/")!
private let archiveURL = "https://pub.example.test/pub/player/ann/games/2026/01"
private let standardPGN =
  "[Event \\\"Live\\\"]\\n[White \\\"Ann\\\"]\\n[Black \\\"Bob\\\"]\\n"
  + "[Result \\\"1-0\\\"]\\n\\n1. e4 e5 2. Nf3 1-0\\n"

private func gameJSON(id: Int, endTime: Int = 1_768_478_400) -> String {
  """
  {"url":"https://www.chess.com/game/live/\(id)","pgn":"\(standardPGN)","time_control":"180+2","end_time":\(endTime),
  "rated":true,"time_class":"blitz","rules":"chess",
  "white":{"rating":1500,"result":"win","username":"Ann"},
  "black":{"rating":1400,"result":"resigned","username":"Bob"}}
  """
}

private func decodeGame(_ json: String) throws -> ChessComGame {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  return try decoder.decode(ChessComGame.self, from: Data(json.utf8))
}

private func makeTransport(_ handler: @escaping @Sendable (URL) -> (Int, Data)) -> FakeTransport {
  FakeTransport { request in
    let (status, body) = handler(request.url!)
    return (status, [:], body)
  }
}

private func makeClient(_ transport: FakeTransport) -> ChessComClient {
  ChessComClient(
    configuration: ChessComConfiguration(baseURL: baseURL, userAgent: "KingsideTests/1.0"),
    transport: transport
  )
}

private func makeClient(_ handler: @escaping @Sendable (URL) -> (Int, Data)) -> ChessComClient {
  makeClient(makeTransport(handler))
}

/// Ann's account: a profile, rapid stats, and two archives. The latest holds game 1, then game 2.
@Sendable
private func annAccount(_ url: URL) -> (Int, Data) {
  switch url.path {
  case "/pub/player/ann": (200, Data(#"{"username":"Ann","joined":1,"last_online":2}"#.utf8))
  case "/pub/player/ann/stats": (200, Data(#"{"chess_rapid":{"last":{"rating":1300}}}"#.utf8))
  case "/pub/player/ann/games/archives":
    (
      200,
      Data(
        #"{"archives":["https://pub.example.test/pub/player/ann/games/2025/12","\#(archiveURL)"]}"#
          .utf8
      )
    )
  case "/pub/player/ann/games/2026/01":
    (
      200,
      Data(
        #"{"games":[\#(gameJSON(id: 1, endTime: 1_000)),\#(gameJSON(id: 2, endTime: 2_000))]}"#
          .utf8
      )
    )
  default: (404, Data())
  }
}

@MainActor
struct AccountTests {
  private let localization = Localization()
  private let suiteName = "ChessUITests.\(UUID().uuidString)"

  /// An account model over fresh settings in which `linked` is the linked username.
  private func makeAccount(
    client: ChessComClient,
    gameLimit: Int = 5,
    linked: String? = "ann"
  ) throws -> (ChessComAccountModel, SettingsStore) {
    let settings = SettingsStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
    settings.value.chessComUsername = linked
    let account = ChessComAccountModel(settings: settings, client: client, gameLimit: gameLimit)
    return (account, settings)
  }

  @Test
  func everyGameCenterReasonHasItsOwnEnglishText() {
    let reasons: [GameCenterUnavailableReason] = [.restricted, .offline, .notSetUp, .other]
    let texts = reasons.map {
      localization.string(AccountLayout.gameCenterDetailKey($0), defaultValue: "\u{0}")
    }
    #expect(!texts.contains("\u{0}"))
    #expect(Set(texts).count == reasons.count)
  }

  @Test
  func ratingsListTimeClassesInOrderAndSkipMissingOnes() throws {
    let stats = try JSONDecoder().decode(
      ChessComStats.self,
      from: Data(
        (#"{"chess_daily":{"last":{"rating":1200}},"chess_blitz":{"last":{"rating":1500},"#
          + #""record":{"win":3,"loss":2,"draw":1}},"chess_bullet":{}}"#).utf8
      )
    )
    let rows = AccountLayout.ratings(stats)
    #expect(rows.map(\.timeClass) == ["blitz", "daily"])
    #expect(rows.map(\.rating) == [1500, 1200])
    let record = try #require(rows[0].record)
    #expect(AccountLayout.record(record, localization: localization) == "3 W · 2 L · 1 D")
    #expect(AccountLayout.timeClassName("blitz", localization: localization) == "Blitz")
    #expect(
      AccountLayout.timeClassName("kingofthehill", localization: localization) == "Kingofthehill"
    )
  }

  @Test
  func gameRowsReadFromTheLinkedPlayersSide() throws {
    let game = try decodeGame(gameJSON(id: 1))
    #expect(AccountLayout.title(game, username: "ANN", localization: localization) == "Bob (1400)")
    #expect(AccountLayout.title(game, username: "bob", localization: localization) == "Ann (1500)")
    #expect(
      AccountLayout.title(game, username: "carl", localization: localization)
        == "Ann (1500) vs Bob (1400)"
    )
    let detail = AccountLayout.detail(
      game,
      username: "ann",
      localization: localization,
      locale: Locale(identifier: "en_US")
    )
    #expect(detail.hasPrefix("You Won! · Blitz · "))
    #expect(
      AccountLayout.detail(
        game,
        username: "bob",
        localization: localization,
        locale: Locale(identifier: "en_US")
      ).hasPrefix("You Lost")
    )
  }

  @Test
  func summaryNamesOnlyTheCountsThatHappened() {
    let summary = ChessComImportSummary(imported: 1, updated: 3, duplicates: 0, skipped: 2)
    #expect(
      AccountLayout.summaryLines(summary, localization: localization) == [
        "1 game imported", "3 games updated", "2 games could not be imported",
      ]
    )
    #expect(AccountLayout.summaryLines(ChessComImportSummary(), localization: localization).isEmpty)
  }

  @Test
  func loadReadsProfileStatsAndTheNewestGamesOfTheLatestArchive() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let (account, _) = try makeAccount(client: makeClient(annAccount), gameLimit: 1)
    await account.load()
    #expect(account.phase == .loaded)
    #expect(account.profile?.username == "Ann")
    #expect(account.stats?.rapid?.last?.rating == 1300)
    #expect(account.games.map(\.url.lastPathComponent) == ["2"])
  }

  @Test
  func loadFailingOnStatsFailsButKeepsTheProfileAndShowsNoGames() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let client = makeClient { url in
      switch url.path {
      case "/pub/player/ann": (200, Data(#"{"username":"Ann","joined":1,"last_online":2}"#.utf8))
      case "/pub/player/ann/games/archives": (200, Data(#"{"archives":["\#(archiveURL)"]}"#.utf8))
      case "/pub/player/ann/games/2026/01": (200, Data(#"{"games":[\#(gameJSON(id: 1))]}"#.utf8))
      default: (500, Data())
      }
    }
    let (account, _) = try makeAccount(client: client)
    await account.load()
    #expect(account.phase == .failed(.network))
    #expect(account.profile?.username == "Ann")
    #expect(account.stats == nil)
    #expect(account.games.isEmpty)
  }

  @Test
  func loadFailingOnTheLatestArchiveFailsButKeepsProfileAndStats() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let client = makeClient { url in
      switch url.path {
      case "/pub/player/ann": (200, Data(#"{"username":"Ann","joined":1,"last_online":2}"#.utf8))
      case "/pub/player/ann/stats": (200, Data(#"{"chess_rapid":{"last":{"rating":1300}}}"#.utf8))
      case "/pub/player/ann/games/archives": (200, Data(#"{"archives":["\#(archiveURL)"]}"#.utf8))
      default: (429, Data())
      }
    }
    let (account, _) = try makeAccount(client: client)
    await account.load()
    #expect(account.phase == .failed(.rateLimited))
    #expect(account.profile?.username == "Ann")
    #expect(account.stats?.rapid?.last?.rating == 1300)
    #expect(account.games.isEmpty)
  }

  @Test
  func linkWritesTheCanonicalUsernameAndForgetsThePreviousAccount() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    let (account, settings) = try makeAccount(client: makeClient(transport))
    await account.load()
    #expect(await account.link(username: "ann") == nil)
    #expect(settings.value.chessComUsername == "Ann")
    // Only the profile check: the Account screen loads the newly linked account.
    #expect(await transport.requests.count == 5)
    #expect(account.phase == .loading)
    #expect(account.profile == nil)
    #expect(account.games.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func unlinkWhileALinkIsCheckingKeepsTheAccountUnlinked() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    await transport.holdRequests()
    let (account, settings) = try makeAccount(client: makeClient(transport), linked: nil)
    let linking = Task { await account.link(username: "ann") }
    try await transport.waitForRequests(count: 1)
    account.unlink()
    await transport.releaseHeldRequest()
    #expect(await linking.value == nil)
    #expect(settings.value.chessComUsername == nil)
  }

  @Test
  func failedLinkReportsNotFoundInvalidAndNetworkFailuresAndLinksNothing() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let missing = makeClient { _ in (404, Data()) }
    let down = makeClient { _ in (500, Data()) }
    let busy = makeClient { _ in (429, Data()) }
    let cases: [(ChessComClient, String, ChessComFailure)] = [
      (missing, "nobody", .notFound), (missing, "no", .invalidUsername),
      (down, "ann", .network), (busy, "ann", .rateLimited),
    ]
    for (client, username, failure) in cases {
      let (account, settings) = try makeAccount(client: client, linked: nil)
      #expect(await account.link(username: username) == failure)
      #expect(settings.value.chessComUsername == nil)
    }
  }

  @Test
  func importUpdatesOldCopiesFromTheLinkedAccountsArchiveOfTheirMonth() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    let (account, _) = try makeAccount(client: makeClient(transport))
    let store = GamePersistenceStore(
      fileURL: FileManager.default.temporaryDirectory.appending(
        path: "AccountTests-\(UUID().uuidString)/games.json"
      )
    )
    let game = try decodeGame(gameJSON(id: 1, endTime: 1_768_478_400))
    _ = await ChessComImporting.importGames([game], username: "ann", into: store)
    // Saved as imports used to be: pass-and-play, neither side marked, January 2026.
    var old = try #require(try await store.allGames().first)
    old.mode = .passAndPlay
    old.white = PlayerInfo(name: old.white.name, rating: old.white.rating)
    try await store.save(old)

    await account.importGames([], into: store)
    #expect(account.importSummary?.updated == 1)
    #expect(await transport.requests.map(\.url?.path) == ["/pub/player/ann/games/2026/01"])
    #expect(try await store.allGames().first?.humanColor == .white)
  }

  @Test
  func unlinkClearsTheSettingAndTheLoadedAccount() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let (account, settings) = try makeAccount(client: makeClient(annAccount))
    await account.load()
    let unwritable = GamePersistenceStore(
      fileURL: URL(filePath: "/nonexistent-\(UUID().uuidString)/games.json")
    )
    await account.importGames(account.games, into: unwritable)
    #expect(account.importSummary != nil)
    account.unlink()
    #expect(settings.value.chessComUsername == nil)
    #expect(account.phase == .loading)
    #expect(account.profile == nil)
    #expect(account.stats == nil)
    #expect(account.games.isEmpty)
    #expect(account.importSummary == nil)
  }

  @Test
  func loadOfAnAccountUnlinkedWhileItRunsAppliesNothing() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    await transport.holdRequests()
    let (account, _) = try makeAccount(client: makeClient(transport))
    let loading = Task { await account.load() }
    try await transport.waitForRequests(count: 1)
    account.unlink()
    for _ in 0..<4 { await transport.releaseHeldRequest() }
    await loading.value
    #expect(await transport.requests.count == 4)
    #expect(account.phase == .loading)
    #expect(account.profile == nil)
    #expect(account.stats == nil)
    #expect(account.games.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func loadOfAnAccountUnlinkedAndLinkedAgainWhileItRunsAppliesNothing() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    await transport.holdRequests()
    let (account, settings) = try makeAccount(client: makeClient(transport), linked: "Ann")
    let loading = Task { await account.load() }
    try await transport.waitForRequests(count: 1)
    account.unlink()
    let linking = Task { await account.link(username: "ann") }
    // The client sends one request at a time: the load's four and the link's one, in any order.
    for _ in 0..<5 { await transport.releaseHeldRequest() }
    #expect(await linking.value == nil)
    await loading.value
    #expect(settings.value.chessComUsername == "Ann")
    #expect(account.phase == .loading)
    #expect(account.profile == nil)
    #expect(account.games.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func cancelledLoadAppliesNothing() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    await transport.holdRequests()
    let (account, _) = try makeAccount(client: makeClient(transport))
    let loading = Task { await account.load() }
    try await transport.waitForRequests(count: 1)
    loading.cancel()
    await loading.value
    #expect(account.phase == .loading)
    #expect(account.profile == nil)
  }

  @Test
  func loadWithoutALinkedAccountMakesNoRequest() async throws {
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let transport = makeTransport(annAccount)
    let (account, _) = try makeAccount(client: makeClient(transport), linked: nil)
    await account.load()
    #expect(await transport.requests.isEmpty)
    #expect(account.profile == nil)
  }
}
