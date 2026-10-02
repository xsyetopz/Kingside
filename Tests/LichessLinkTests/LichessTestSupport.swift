import Foundation
import HTTPSupport
import HTTPSupportTests
import Testing
@testable import LichessLink

/// Fails every request the way `URLSessionTransport` does when the response is not HTTP.
func nonHTTPTransport() -> FakeTransport {
  FakeTransport { _ in throw HTTPTransportError.invalidResponse }
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
  _ handler: @escaping FakeTransport.Handler = { _ in (200, [:], Data("{\"ok\":true}".utf8))
  }
) -> (LichessClient, FakeTransport) {
  let transport = FakeTransport(
    streamLines: streamLines,
    keepStreamsOpen: keepStreamOpen,
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
