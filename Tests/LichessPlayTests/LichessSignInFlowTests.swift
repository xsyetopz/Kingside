import Foundation
import HTTPSupportTests
import LichessLink
import LichessPlay
import Testing

/// Stands in for the system browser session: records what the flow opens, and answers with the
/// callback that `answer` builds from the `state` the flow sent.
private actor FakeBrowser {
  private(set) var authorizeURL: URL?
  private(set) var callbackScheme: String?
  private let answer: @Sendable (_ state: String) throws -> URL?

  init(answer: @escaping @Sendable (_ state: String) throws -> URL?) {
    self.answer = answer
  }

  func authenticate(_ url: URL, _ scheme: String) throws -> URL? {
    authorizeURL = url
    callbackScheme = scheme
    return try answer(query(url)["state"] ?? "")
  }
}

private struct BrowserFailure: Error, Equatable {}

private func query(_ url: URL) -> [String: String] {
  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
  return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

private func form(_ body: Data?) -> [String: String] {
  let pairs = String(bytes: body ?? Data(), encoding: .utf8)?.split(separator: "&") ?? []
  return Dictionary(
    uniqueKeysWithValues: pairs.map {
      let parts = $0.split(separator: "=", maxSplits: 1)
      return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
    }
  )
}

private func callback(_ query: String) -> URL {
  URL(string: "kingside://oauth/lichess?\(query)")!
}

private let tokenBody = Data(#"{"token_type":"Bearer","access_token":"lio_abc"}"#.utf8)

struct LichessSignInFlowTests {
  private func makeFlow(transport: FakeTransport) -> LichessSignInFlow {
    let configuration = LichessConfiguration(
      baseURL: URL(string: "https://lichess.example.test")!,
      userAgent: "KingsideTests/1.0 (+tests)",
      clientID: "kingside-tests",
      redirectURI: URL(string: "kingside://oauth/lichess")!
    )
    return LichessSignInFlow(
      oauth: LichessOAuth(configuration: configuration, transport: transport),
      callbackScheme: "kingside"
    )
  }

  private func run(
    _ flow: LichessSignInFlow,
    browser: FakeBrowser
  ) async throws -> String? {
    try await flow.run { try await browser.authenticate($0, $1) }
  }

  @Test
  func successExchangesTheCodeWithTheVerifierOfTheChallenge() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let browser = FakeBrowser { callback("code=abc&state=\($0)") }

    let token = try await run(makeFlow(transport: transport), browser: browser)

    #expect(token == "lio_abc")
    #expect(await browser.callbackScheme == "kingside")
    let authorizeURL = try #require(await browser.authorizeURL)
    #expect(authorizeURL.absoluteString.hasPrefix("https://lichess.example.test/oauth?"))
    #expect(await transport.paths == ["POST /api/token"])
    let request = try #require(await transport.requests.first)
    let sent = form(request.httpBody)
    #expect(sent["code"] == "abc")
    let verifier = try #require(sent["code_verifier"])
    #expect(LichessOAuth.challenge(for: verifier) == query(authorizeURL)["code_challenge"])
  }

  @Test
  func eachRunSendsAFreshStateAndChallenge() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let first = FakeBrowser { _ in nil }
    let second = FakeBrowser { _ in nil }

    _ = try await run(makeFlow(transport: transport), browser: first)
    _ = try await run(makeFlow(transport: transport), browser: second)

    let one = query(try #require(await first.authorizeURL))
    let two = query(try #require(await second.authorizeURL))
    #expect(one["state"]?.isEmpty == false)
    #expect(one["state"] != two["state"])
    #expect(one["code_challenge"] != two["code_challenge"])
  }

  @Test
  func aDeniedCallbackIsRejectedBeforeTheExchange() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let browser = FakeBrowser { callback("error=access_denied&state=\($0)") }

    await #expect(throws: LichessOAuth.CallbackFailure.denied) {
      try await run(makeFlow(transport: transport), browser: browser)
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func closingTheBrowserReturnsNoTokenAndSendsNothing() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let browser = FakeBrowser { _ in nil }

    let token = try await run(makeFlow(transport: transport), browser: browser)

    #expect(token == nil)
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func aCallbackWithAnotherStateIsRejectedBeforeTheExchange() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let browser = FakeBrowser { _ in callback("code=abc&state=forged") }

    await #expect(throws: LichessOAuth.CallbackFailure.stateMismatch) {
      try await run(makeFlow(transport: transport), browser: browser)
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func aCallbackWithoutACodeIsRejectedBeforeTheExchange() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let browser = FakeBrowser { callback("state=\($0)") }

    await #expect(throws: LichessOAuth.CallbackFailure.missingCode) {
      try await run(makeFlow(transport: transport), browser: browser)
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test
  func aFailedExchangeThrowsItsError() async throws {
    let transport = FakeTransport { _ in (400, [:], Data(#"{"error":"invalid_grant"}"#.utf8)) }
    let browser = FakeBrowser { callback("code=abc&state=\($0)") }

    await #expect(throws: LichessError.http(status: 400)) {
      try await run(makeFlow(transport: transport), browser: browser)
    }
  }

  @Test
  func aBrowserFailureThrowsItsError() async throws {
    let transport = FakeTransport { _ in (200, [:], tokenBody) }
    let browser = FakeBrowser { _ in throw BrowserFailure() }

    await #expect(throws: BrowserFailure()) {
      try await run(makeFlow(transport: transport), browser: browser)
    }
    #expect(await transport.requests.isEmpty)
  }
}
