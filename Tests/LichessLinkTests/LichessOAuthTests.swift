import Foundation
import HTTPSupportTests
import Testing
@testable import LichessLink

@Suite
struct LichessOAuthTests {
  @Test
  func challengeMatchesRFC7636AppendixB() {
    #expect(
      LichessOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )
  }

  @Test
  func verifierIsRandomBase64URL() throws {
    let a = try LichessOAuth.makeVerifier()
    let b = try LichessOAuth.makeVerifier()
    #expect(a != b)
    #expect(a.count >= 43)
    #expect(a.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
  }

  @Test
  func authorizeURLQuery() throws {
    let oauth = LichessOAuth(
      configuration: testConfiguration,
      transport: FakeTransport { _ in (200, [:], Data()) }
    )
    let url = oauth.authorizeURL(state: "st4te", challenge: "chal")
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "lichess.example.test")
    #expect(components.path == "/oauth")
    let items = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
    )
    #expect(items.count == 7)
    #expect(items["response_type"] == "code")
    #expect(items["client_id"] == "kingside-tests")
    #expect(items["redirect_uri"] == "kingside://oauth/lichess")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["code_challenge"] == "chal")
    #expect(items["scope"] == "board:play challenge:read challenge:write")
    #expect(items["state"] == "st4te")
  }

  @Test
  func exchangePostsFormAndReturnsToken() async throws {
    let transport = FakeTransport { _ in
      (
        200, [:],
        Data(#"{"token_type":"Bearer","access_token":"lio_abc","expires_in":31536000}"#.utf8)
      )
    }
    let token = try await LichessOAuth(configuration: testConfiguration, transport: transport)
      .exchange(code: "the code", verifier: "ver")
    #expect(token == "lio_abc")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/token")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
    )
    #expect(
      String(bytes: request.httpBody ?? Data(), encoding: .utf8)
        == "grant_type=authorization_code&code=the%20code&code_verifier=ver"
        + "&redirect_uri=kingside%3A%2F%2Foauth%2Flichess&client_id=kingside-tests"
    )
  }

  @Test
  func exchangeMapsFailure() async throws {
    let transport = FakeTransport { _ in (400, [:], Data(#"{"error":"invalid_grant"}"#.utf8))
    }
    let oauth = LichessOAuth(configuration: testConfiguration, transport: transport)
    await #expect(throws: LichessError.http(status: 400)) {
      try await oauth.exchange(code: "c", verifier: "v")
    }
  }

  @Test
  func exchangeMapsTooManyRequestsToRateLimited() async throws {
    let transport = FakeTransport { _ in (429, [:], Data()) }
    let oauth = LichessOAuth(configuration: testConfiguration, transport: transport)
    await #expect(throws: LichessError.rateLimited) {
      try await oauth.exchange(code: "c", verifier: "v")
    }
  }

  @Test
  func exchangeNonHTTPResponseThrowsInvalidResponse() async {
    let oauth = LichessOAuth(configuration: testConfiguration, transport: nonHTTPTransport())
    await #expect(throws: LichessError.invalidResponse) {
      try await oauth.exchange(code: "c", verifier: "v")
    }
  }

  private func code(
    _ query: String,
    state: String = "s1"
  ) -> Result<String, LichessOAuth.CallbackFailure> {
    LichessOAuth.code(
      from: URL(string: "io.github.xsyetopz.kingside://oauth?\(query)")!,
      expectedState: state
    )
  }

  @Test
  func callbackCodeIsReturnedWhenStateMatches() {
    #expect(code("code=abc&state=s1") == .success("abc"))
  }

  @Test
  func callbackWithAWrongOrMissingStateIsRejected() {
    #expect(code("code=abc&state=other") == .failure(.stateMismatch))
    #expect(code("code=abc") == .failure(.stateMismatch))
  }

  @Test
  func callbackErrorParameterIsDenied() {
    #expect(code("error=access_denied&state=s1") == .failure(.denied))
    // A forged error does not get past the state check.
    #expect(code("error=access_denied&state=x") == .failure(.stateMismatch))
  }

  @Test
  func callbackWithAMissingOrEmptyCodeIsRejected() {
    #expect(code("state=s1") == .failure(.missingCode))
    #expect(code("code=&state=s1") == .failure(.missingCode))
  }

  @Test
  func inMemoryTokenStoreRoundTrips() throws {
    let store = InMemoryTokenStore()
    #expect(store.token() == nil)
    try store.save("abc")
    #expect(store.token() == "abc")
    try store.delete()
    #expect(store.token() == nil)
  }
}
