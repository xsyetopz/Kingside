import Foundation
import LichessLink

/// The parts of the Lichess sign-in that need no UI, so tests can reach them.
enum LichessSignIn {
    /// Why an OAuth callback gives no authorization code.
    enum CallbackFailure: Error, Equatable {
        /// `state` is missing or differs from the one the app sent.
        case stateMismatch
        /// Lichess answered with an `error` parameter, such as `access_denied`.
        case denied
        case missingCode
    }

    /// The authorization code in the callback `url`, once `state` is checked against `expectedState`.
    static func code(from url: URL, expectedState: String) -> Result<String, CallbackFailure> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { return .failure(.stateMismatch) }
        if value("error") != nil { return .failure(.denied) }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        return .success(code)
    }

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
