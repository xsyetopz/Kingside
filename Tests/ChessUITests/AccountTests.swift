import ChessComLink
import ChessContent
import ChessOnline
import ChessPlay
import Foundation
import HTTPSupport
import Testing
@testable import ChessUI

/// Answers each request from `handler`, like the transport double of `ChessComLinkTests`.
private struct StubTransport: HTTPTransport {
  let handler: @Sendable (URL) -> (Int, Data)

  func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
    let url = try #require(request.url)
    let (status, body) = handler(url)
    return (
      body,
      try #require(
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
      )
    )
  }
}

private let baseURL = URL(string: "https://pub.example.test/pub/")!
private let archiveURL = "https://pub.example.test/pub/player/ann/games/2026/01"
private let standardPGN =
  "[Event \\\"Live\\\"]\\n[White \\\"Ann\\\"]\\n[Black \\\"Bob\\\"]\\n"
  + "[Result \\\"1-0\\\"]\\n\\n1. e4 e5 2. Nf3 1-0\\n"

private func gameJSON(
  id: Int,
  rules: String = "chess",
  endTime: Int = 1_768_478_400,
  whiteResult: String = "win",
  blackResult: String = "resigned"
) -> String {
  """
  {"url":"https://www.chess.com/game/live/\(id)","pgn":"\(standardPGN)","time_control":"180+2","end_time":\(endTime),
  "rated":true,"time_class":"blitz","rules":"\(rules)",
  "white":{"rating":1500,"result":"\(whiteResult)","username":"Ann"},
  "black":{"rating":1400,"result":"\(blackResult)","username":"Bob"}}
  """
}

private func decodeGame(_ json: String) throws -> ChessComGame {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  return try decoder.decode(ChessComGame.self, from: Data(json.utf8))
}

private func makeClient(_ handler: @escaping @Sendable (URL) -> (Int, Data)) -> ChessComClient {
  ChessComClient(
    configuration: ChessComConfiguration(baseURL: baseURL, userAgent: "KingsideTests/1.0"),
    transport: StubTransport(handler: handler)
  )
}

@MainActor
struct AccountTests {
  private let localization = Localization()

  private func makeStore() -> GamePersistenceStore {
    GamePersistenceStore(
      fileURL: FileManager.default.temporaryDirectory.appending(
        path: "AccountTests-\(UUID().uuidString)/games.json"
      )
    )
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
    let summary = ChessComImportSummary(imported: 1, duplicates: 0, skipped: 2)
    #expect(
      AccountLayout.summaryLines(summary, localization: localization) == [
        "1 game imported", "2 games could not be imported",
      ]
    )
    #expect(AccountLayout.summaryLines(ChessComImportSummary(), localization: localization).isEmpty)
  }

  @Test
  func timeControlsResultsAndTerminationsMap() {
    #expect(
      ChessComImporting.timeControl("180+2")
        == TimeControl(initialSeconds: 180, incrementSeconds: 2)
    )
    #expect(
      ChessComImporting.timeControl("600") == TimeControl(initialSeconds: 600, incrementSeconds: 0)
    )
    #expect(ChessComImporting.timeControl("1/86400") == .untimed)
    #expect(ChessComImporting.result(white: .win, black: .checkmated) == .whiteWon)
    #expect(ChessComImporting.result(white: .timeout, black: .win) == .blackWon)
    #expect(ChessComImporting.result(white: .agreed, black: .agreed) == .draw)
    #expect(ChessComImporting.termination(white: .win, black: .checkmated) == .checkmate)
    #expect(ChessComImporting.termination(white: .resigned, black: .win) == .resignation)
    #expect(ChessComImporting.termination(white: .fiftyMove, black: .fiftyMove) == .fiftyMoveRule)
    #expect(ChessComImporting.termination(white: .win, black: .other("abandoned")) == nil)
  }

  @Test
  func gameIDsAreStablePerURL() throws {
    let one = try #require(URL(string: "https://www.chess.com/game/live/1"))
    let two = try #require(URL(string: "https://www.chess.com/game/live/2"))
    let first = ChessComImporting.savedGameID(for: one)
    let second = ChessComImporting.savedGameID(for: one)
    #expect(first == second)
    #expect(first != ChessComImporting.savedGameID(for: two))
  }

  @Test
  func importIntoUnreadableArchiveSkipsEveryGame() async throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appending(path: "AccountTests-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let damaged = Data("not json".utf8)
    try damaged.write(to: fileURL)
    let games = [try decodeGame(gameJSON(id: 1)), try decodeGame(gameJSON(id: 2))]

    let summary = await ChessComImporting.importGames(
      games,
      username: "ann",
      into: GamePersistenceStore(fileURL: fileURL)
    )
    #expect(summary == ChessComImportSummary(imported: 0, duplicates: 0, skipped: 2))
    #expect(try Data(contentsOf: fileURL) == damaged)
  }

  @Test
  func importSkipsDuplicatesAndVariants() async throws {
    let store = makeStore()
    let games = [
      try decodeGame(gameJSON(id: 1)), try decodeGame(gameJSON(id: 2)),
      try decodeGame(gameJSON(id: 3, rules: "chess960")),
    ]

    let first = await ChessComImporting.importGames(games, username: "ann", into: store)
    #expect(first == ChessComImportSummary(imported: 2, duplicates: 0, skipped: 1))
    let second = await ChessComImporting.importGames(games, username: "ann", into: store)
    #expect(second == ChessComImportSummary(imported: 0, duplicates: 2, skipped: 1))

    let saved = try await store.allGames()
    #expect(saved.count == 2)
    let one = try #require(
      saved.first { $0.id == ChessComImporting.savedGameID(for: games[0].url) }
    )
    #expect(one.white.name == "Ann" && one.black.name == "Bob")
    #expect(one.result == .whiteWon && one.termination == .resignation && one.isFinished)
    #expect(one.game.moves.count == 3)
    #expect(one.timeControl == TimeControl(initialSeconds: 180, incrementSeconds: 2))
  }

  @Test
  func loadReadsProfileStatsAndTheNewestGamesOfTheLatestArchive() async throws {
    let older = gameJSON(id: 1, endTime: 1_000)
    let newer = gameJSON(id: 2, endTime: 2_000)
    let client = makeClient { url in
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
      case "/pub/player/ann/games/2026/01": (200, Data(#"{"games":[\#(older),\#(newer)]}"#.utf8))
      default: (404, Data())
      }
    }
    let account = ChessComAccountModel(username: "ann", client: client, gameLimit: 1)
    await account.load()
    #expect(account.phase == .loaded)
    #expect(account.profile?.username == "Ann")
    #expect(account.stats?.rapid?.last?.rating == 1300)
    #expect(account.games.map(\.url.lastPathComponent) == ["2"])
  }

  @Test
  func loadFailingOnStatsFailsButKeepsTheProfileAndShowsNoGames() async {
    let client = makeClient { url in
      switch url.path {
      case "/pub/player/ann": (200, Data(#"{"username":"Ann","joined":1,"last_online":2}"#.utf8))
      case "/pub/player/ann/games/archives": (200, Data(#"{"archives":["\#(archiveURL)"]}"#.utf8))
      case "/pub/player/ann/games/2026/01": (200, Data(#"{"games":[\#(gameJSON(id: 1))]}"#.utf8))
      default: (500, Data())
      }
    }
    let account = ChessComAccountModel(username: "ann", client: client, gameLimit: 5)
    await account.load()
    #expect(account.phase == .failed(.network))
    #expect(account.profile?.username == "Ann")
    #expect(account.stats == nil)
    #expect(account.games.isEmpty)
  }

  @Test
  func loadFailingOnTheLatestArchiveFailsButKeepsProfileAndStats() async {
    let client = makeClient { url in
      switch url.path {
      case "/pub/player/ann": (200, Data(#"{"username":"Ann","joined":1,"last_online":2}"#.utf8))
      case "/pub/player/ann/stats": (200, Data(#"{"chess_rapid":{"last":{"rating":1300}}}"#.utf8))
      case "/pub/player/ann/games/archives": (200, Data(#"{"archives":["\#(archiveURL)"]}"#.utf8))
      default: (429, Data())
      }
    }
    let account = ChessComAccountModel(username: "ann", client: client, gameLimit: 5)
    await account.load()
    #expect(account.phase == .failed(.rateLimited))
    #expect(account.profile?.username == "Ann")
    #expect(account.stats?.rapid?.last?.rating == 1300)
    #expect(account.games.isEmpty)
  }

  @Test
  func linkingReportsNotFoundInvalidAndNetworkFailures() async {
    let missing = makeClient { _ in (404, Data()) }
    let down = makeClient { _ in (500, Data()) }
    let busy = makeClient { _ in (429, Data()) }
    #expect(
      await ChessComAccountModel.verify(username: "nobody", client: missing) == .failure(.notFound)
    )
    #expect(
      await ChessComAccountModel.verify(username: "no", client: missing)
        == .failure(.invalidUsername)
    )
    #expect(await ChessComAccountModel.verify(username: "ann", client: down) == .failure(.network))
    #expect(
      await ChessComAccountModel.verify(username: "ann", client: busy) == .failure(.rateLimited)
    )
    let found = makeClient { _ in
      (200, Data(#"{"username":"Ann","joined":1,"last_online":2}"#.utf8))
    }
    let result = await ChessComAccountModel.verify(username: "ann", client: found)
    #expect((try? result.get())?.username == "Ann")
  }
}
