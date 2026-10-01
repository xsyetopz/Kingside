import Foundation

/// Endpoints of outside services, decoded from `services.json`.
public struct ServiceEndpoints: Codable, Hashable, Sendable {
  /// Named in the `User-Agent` of every service, which ask API clients for a contact.
  public let contact: String
  public let chessCom: ChessComEndpoints
  public let lichess: LichessEndpoints

  /// `<product>/<version> (+<contact>)`.
  public func userAgent(product: String, version: String) -> String {
    "\(product)/\(version) (+\(contact))"
  }
}

/// The Chess.com Published-Data API.
public struct ChessComEndpoints: Codable, Hashable, Sendable {
  public let baseURL: URL
}

/// The Lichess site, and the OAuth client the app signs in with.
public struct LichessEndpoints: Codable, Hashable, Sendable {
  public let baseURL: URL
  /// Lichess has no client registration; this is any string that names the app.
  public let clientID: String
  /// A custom URL scheme that the OAuth flow returns to.
  public let redirectURI: URL

  /// The Lichess report form for `username`, which is percent-encoded.
  public func reportURL(username: String) -> URL? {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    guard let name = username.addingPercentEncoding(withAllowedCharacters: safe) else { return nil }
    return URL(string: baseURL.appending(path: "report").absoluteString + "?username=" + name)
  }
}
