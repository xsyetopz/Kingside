import Foundation
import Testing
@testable import LichessLink

/// Records every request, answers through `handler`, and tracks how many requests overlap.
actor FakeLichessTransport: LichessTransport {
  typealias Handler = @Sendable (URLRequest) -> (Int, [String: String], Data)

  private(set) var requests: [URLRequest] = []
  private(set) var maxConcurrency = 0
  private(set) var streamTerminated = false
  private var inFlight = 0
  private let handler: Handler
  private let streamLines: [String]
  private let keepStreamOpen: Bool

  init(streamLines: [String] = [], keepStreamOpen: Bool = false, handler: @escaping Handler) {
    self.handler = handler
    self.streamLines = streamLines
    self.keepStreamOpen = keepStreamOpen
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    inFlight += 1
    maxConcurrency = max(maxConcurrency, inFlight)
    try await Task.sleep(for: .milliseconds(20))
    inFlight -= 1
    let (status, headers, body) = handler(request)
    return (
      body,
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  func lines(
    for request: URLRequest
  ) throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
    requests.append(request)
    let (status, headers, _) = handler(request)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: nil,
      headerFields: headers
    )!
    let lines = streamLines
    let keepOpen = keepStreamOpen
    let stream = AsyncThrowingStream<String, Error> { continuation in
      for line in lines { continuation.yield(line) }
      if !keepOpen { continuation.finish() }
      continuation.onTermination = { _ in Task { await self.markTerminated() } }
    }
    return (response, stream)
  }

  private func markTerminated() { streamTerminated = true }
}

/// A mutable clock for the rate-limit back-off.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_000_000)

  var now: Date { lock.withLock { current } }
  func advance(_ seconds: TimeInterval) {
    lock.withLock { current = current.addingTimeInterval(seconds) }
  }
}

let testConfiguration = LichessConfiguration(
  baseURL: URL(string: "https://lichess.example.test")!,
  userAgent: "KingsideTests/1.0 (contact: tests@example.invalid)",
  clientID: "kingside-tests",
  redirectURI: URL(string: "kingside://oauth/lichess")!
)

func fixtureData(_ name: String, _ ext: String = "json") throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
  )
  return try Data(contentsOf: url)
}

func fixtureLines(_ name: String) throws -> [String] {
  try #require(String(bytes: try fixtureData(name, "ndjson"), encoding: .utf8))
    .components(separatedBy: "\n")
}

func makeClient(
  token: String? = "tok",
  clock: TestClock = TestClock(),
  streamLines: [String] = [],
  keepStreamOpen: Bool = false,
  _ handler: @escaping FakeLichessTransport.Handler = { _ in (200, [:], Data("{\"ok\":true}".utf8))
  }
) -> (LichessClient, FakeLichessTransport) {
  let transport = FakeLichessTransport(
    streamLines: streamLines,
    keepStreamOpen: keepStreamOpen,
    handler: handler
  )
  let client = LichessClient(
    configuration: testConfiguration,
    transport: transport,
    tokenProvider: { token },
    now: { clock.now }
  )
  return (client, transport)
}
