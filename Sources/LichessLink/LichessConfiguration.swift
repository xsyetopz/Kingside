import Foundation

/// Values the caller injects into `LichessClient` and `LichessOAuth`; neither hard-codes them.
public struct LichessConfiguration: Sendable, Equatable {
  /// Lichess root, for example `https://lichess.org`.
  public var baseURL: URL
  /// Sent as `User-Agent`; Lichess asks that it identifies the app and includes contact
  /// information.
  public var userAgent: String
  /// OAuth client id. Lichess has no client registration, so this is any unique string naming the
  /// app.
  public var clientID: String
  /// Where the OAuth flow returns to with the authorization code.
  public var redirectURI: URL

  public init(baseURL: URL, userAgent: String, clientID: String, redirectURI: URL) {
    self.baseURL = baseURL
    self.userAgent = userAgent
    self.clientID = clientID
    self.redirectURI = redirectURI
  }
}

public enum LichessError: Error, Equatable, Sendable {
  /// HTTP 401: the token is missing, expired, or revoked.
  case unauthorized
  /// HTTP 429, or a request made during the back-off that follows one.
  case rateLimited
  case http(status: Int)
  case invalidResponse
  case decoding(String)
  /// A path component or parameter failed validation; no request was sent.
  case invalidArgument(String)
}
