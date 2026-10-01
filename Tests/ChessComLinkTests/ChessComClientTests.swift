import Foundation
import HTTPSupport
import Testing
@testable import ChessComLink

/// Records every request, answers through `handler`, and tracks how many requests overlap.
actor FakeTransport: HTTPTransport {
  typealias Handler = @Sendable (URLRequest) -> (Int, [String: String], Data)

  private(set) var requests: [URLRequest] = []
  private(set) var maxConcurrency = 0
  private var inFlight = 0
  private let handler: Handler

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    inFlight += 1
    maxConcurrency = max(maxConcurrency, inFlight)
    try await Task.sleep(for: .milliseconds(20))
    inFlight -= 1
    let (status, headers, body) = handler(request)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: nil,
      headerFields: headers
    )!
    return (body, response)
  }
}

let testConfiguration = ChessComConfiguration(
  baseURL: URL(string: "https://pub.example.test/pub/")!,
  userAgent: "KingsideTests/1.0 (contact: tests@example.invalid)"
)

func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
  )
  return try Data(contentsOf: url)
}

func makeClient(_ handler: @escaping FakeTransport.Handler) -> (ChessComClient, FakeTransport) {
  let transport = FakeTransport(handler: handler)
  return (ChessComClient(configuration: testConfiguration, transport: transport), transport)
}

@Suite
struct ChessComClientTests {
  @Test
  func buildsURLsAndSendsUserAgent() async throws {
    let profile = try fixture("profile")
    let stats = try fixture("stats")
    let archives = try fixture("archives")
    let games = try fixture("games")
    let (client, transport) = makeClient { request in
      let body =
        switch request.url!.path {
        case "/pub/player/hikaru": profile
        case "/pub/player/hikaru/stats": stats
        case "/pub/player/hikaru/games/archives": archives
        default: games
        }
      return (200, [:], body)
    }
    _ = try await client.profile(username: "hikaru")
    _ = try await client.stats(username: "hikaru")
    _ = try await client.archives(username: "hikaru")
    _ = try await client.games(username: "hikaru", year: 2014, month: 1)
    let requests = await transport.requests
    #expect(
      requests.map { $0.url!.absoluteString } == [
        "https://pub.example.test/pub/player/hikaru",
        "https://pub.example.test/pub/player/hikaru/stats",
        "https://pub.example.test/pub/player/hikaru/games/archives",
        "https://pub.example.test/pub/player/hikaru/games/2014/01",
      ]
    )
    for request in requests {
      #expect(request.value(forHTTPHeaderField: "User-Agent") == testConfiguration.userAgent)
      #expect(request.httpMethod == "GET")
    }
  }

  @Test
  func decodesFixtures() async throws {
    let profile = try fixture("profile")
    let stats = try fixture("stats")
    let games = try fixture("games")
    let (client, _) = makeClient { request in
      (
        200, [:],
        request.url!.path.hasSuffix("stats")
          ? stats : request.url!.path.contains("games") ? games : profile
      )
    }
    let p = try await client.profile(username: "Hikaru")
    #expect(p.username == "hikaru")
    #expect(p.name == "Hikaru Nakamura")
    #expect(p.country?.lastPathComponent == "US")
    #expect(p.joined == Date(timeIntervalSince1970: 1_389_043_258))
    let s = try await client.stats(username: "hikaru")
    #expect(s.blitz?.last?.rating == 3471)
    #expect(s.daily?.record?.win == 73)
    #expect(s.rapid?.best?.rating == 2927)
    let g = try await client.games(username: "hikaru", year: 2014, month: 1)
    #expect(g.count == 1)
    #expect(g[0].timeClass == "blitz")
    #expect(g[0].white.username == "Hikaru")
    #expect(g[0].black.rating == 2167)
    #expect(g[0].rated)
  }

  @Test(arguments: [
    "", "ab", "has space", "../admin", "a/b/c", "user?x=1", "üñíçode", "UPPER%2F",
    String(repeating: "a", count: 26),
  ])
  func invalidUsernameMakesNoRequest(_ username: String) async throws {
    let (client, transport) = makeClient { _ in (200, [:], Data()) }
    await #expect(throws: ChessComError.invalidUsername) {
      try await client.profile(username: username)
    }
    await #expect(throws: ChessComError.invalidUsername) {
      try await client.games(username: username, year: 2020, month: 1)
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func usernameIsTrimmedAndLowercased() async throws {
    let profile = try fixture("profile")
    let (client, transport) = makeClient { _ in (200, [:], profile) }
    _ = try await client.profile(username: "  Some_User-1 \n")
    #expect(await transport.requests.first?.url?.path == "/pub/player/some_user-1")
  }

  @Test
  func etagRoundTripAndNotModified() async throws {
    let profile = try fixture("profile")
    let (client, transport) = makeClient { request in
      if request.value(forHTTPHeaderField: "If-None-Match") == "W/\"v1\"" {
        return (304, [:], Data())
      }
      return (200, ["ETag": "W/\"v1\""], profile)
    }
    let first = try await client.profile(username: "hikaru")
    let second = try await client.profile(username: "hikaru")
    #expect(first == second)
    let requests = await transport.requests
    #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == "W/\"v1\"")
  }

  @Test
  func notModifiedWithoutCacheIsHTTPError() async throws {
    let (client, _) = makeClient { _ in (304, [:], Data()) }
    await #expect(throws: ChessComError.http(status: 304)) {
      try await client.profile(username: "hikaru")
    }
  }

  @Test
  func mapsErrorStatuses() async throws {
    let (client, _) = makeClient { request in
      switch request.url!.lastPathComponent {
      case "missing": (404, [:], Data())
      case "limited": (429, ["Retry-After": "30"], Data())
      case "limitednohint": (429, [:], Data())
      case "broken": (503, [:], Data())
      default: (200, [:], Data("{".utf8))
      }
    }
    await #expect(throws: ChessComError.notFound) { try await client.profile(username: "missing") }
    await #expect(throws: ChessComError.rateLimited(retryAfter: 30)) {
      try await client.profile(username: "limited")
    }
    await #expect(throws: ChessComError.rateLimited(retryAfter: nil)) {
      try await client.profile(username: "limitednohint")
    }
    await #expect(throws: ChessComError.http(status: 503)) {
      try await client.profile(username: "broken")
    }
    await #expect {
      try await client.profile(username: "garbage")
    } throws: { error in
      if case .decoding = error as? ChessComError { true } else { false }
    }
  }

  @Test
  func nonHTTPResponseIsInvalidResponse() async {
    struct NonHTTPTransport: HTTPTransport {
      func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        throw HTTPTransportError.invalidResponse
      }
    }
    let client = ChessComClient(configuration: testConfiguration, transport: NonHTTPTransport())
    await #expect(throws: ChessComError.invalidResponse) {
      try await client.profile(username: "hikaru")
    }
  }

  @Test
  func requestsAreSerial() async throws {
    let profile = try fixture("profile")
    let (client, transport) = makeClient { _ in (200, [:], profile) }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<5 {
        group.addTask { _ = try await client.profile(username: "hikaru") }
      }
      try await group.waitForAll()
    }
    #expect(await transport.requests.count == 5)
    #expect(await transport.maxConcurrency == 1)
  }

  @Test
  func serialQueueSurvivesAFailedRequest() async throws {
    let profile = try fixture("profile")
    let (client, _) = makeClient { request in
      request.url!.lastPathComponent == "missing" ? (404, [:], Data()) : (200, [:], profile)
    }
    await #expect(throws: ChessComError.notFound) { try await client.profile(username: "missing") }
    #expect(try await client.profile(username: "hikaru").username == "hikaru")
  }

  @Test
  func archiveURLsMustBeOnConfiguredHost() async throws {
    let games = try fixture("games")
    let (client, transport) = makeClient { _ in (200, [:], games) }
    for bad in [
      "https://evil.example.test/pub/player/hikaru/games/2014/01",
      "http://pub.example.test/pub/player/hikaru/games/2014/01",
      "https://pub.example.test.evil.test/pub/player/hikaru/games/2014/01",
      "https://pub.example.test/other/player/hikaru/games/2014/01",
    ] {
      await #expect(throws: ChessComError.invalidArchive) {
        try await client.games(archiveURL: URL(string: bad)!)
      }
    }
    #expect(await transport.requests.isEmpty)
    let good = URL(string: "https://pub.example.test/pub/player/hikaru/games/2014/01")!
    #expect(try await client.games(archiveURL: good).count == 1)
  }

  @Test
  func rejectsOutOfRangeMonth() async throws {
    let (client, transport) = makeClient { _ in (200, [:], Data()) }
    await #expect(throws: ChessComError.invalidArchive) {
      try await client.games(username: "hikaru", year: 2020, month: 13)
    }
    #expect(await transport.requests.isEmpty)
  }
}
