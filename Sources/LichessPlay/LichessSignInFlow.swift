import Foundation
import LichessLink

/// The Lichess authorization-code sign-in with PKCE, up to the access token.
/// The platform browser session is injected, so the flow runs without UI.
public struct LichessSignInFlow: Sendable {
  /// Opens `authorizeURL` in a browser session and returns the callback URL with the scheme
  /// `callbackScheme`, or `nil` when the player closes the session.
  public typealias Authenticate =
    @Sendable (_ authorizeURL: URL, _ callbackScheme: String) async throws -> URL?

  private let oauth: LichessOAuth
  private let callbackScheme: String

  public init(oauth: LichessOAuth, callbackScheme: String) {
    self.oauth = oauth
    self.callbackScheme = callbackScheme
  }

  /// The access token, or `nil` when the player closed the browser session.
  /// Throws `LichessOAuth.CallbackFailure` for a callback without a valid code, and the
  /// `authenticate` or token exchange error otherwise. Throws `LichessError.invalidResponse`
  /// before opening the browser when the system cannot generate random bytes.
  public func run(authenticate: Authenticate) async throws -> String? {
    let verifier = try LichessOAuth.makeVerifier()
    let state = try LichessOAuth.makeState()
    let url = oauth.authorizeURL(state: state, challenge: LichessOAuth.challenge(for: verifier))
    guard let callback = try await authenticate(url, callbackScheme) else { return nil }
    let code = try LichessOAuth.code(from: callback, expectedState: state).get()
    return try await oauth.exchange(code: code, verifier: verifier)
  }
}
