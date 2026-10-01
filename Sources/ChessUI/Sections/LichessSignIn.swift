import Foundation
import LichessLink

/// The parts of the Lichess sign-in that need no UI, so tests can reach them.
enum LichessSignIn {
  /// The Lichess page that creates a personal token with the scopes the app needs.
  /// It is built as text: `[]` must stay as they are, and tvOS only shows the address.
  static func tokenCreationURL(baseURL: URL) -> String {
    let scopes = LichessOAuth.scope.split(separator: " ").map { "scopes[]=\($0)" }
    let query = (scopes + ["description=Kingside"]).joined(separator: "&")
    return baseURL.appending(path: "account/oauth/token/create").absoluteString + "?" + query
  }
}

extension LichessFailure {
  /// Localisation key of the message.
  var messageKey: String {
    switch self {
    case .unauthorized: "account.lichess.error.unauthorized"
    case .rateLimited: "account.lichess.error.rateLimited"
    case .network: "account.lichess.error.network"
    case .notAllowed: "online.error.notAllowed"
    }
  }
}
