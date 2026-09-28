import Foundation

/// Chess.com login is only enabled after Chess.com approves the app for OAuth access.
/// The app never accepts or stores a Chess.com password.
protocol ChessComAccountAuthorizing: Sendable {
    var isConfigured: Bool { get }
    func authorize() async throws -> AuthorizedChessComAccount
    func signOut() async
}

struct AuthorizedChessComAccount: Codable, Equatable, Sendable {
    let username: String
    let accessToken: String
    let expiration: Date
}

struct ChessComOAuthConfiguration: Sendable {
    let clientID: String
    let redirectURI: URL

    static var bundled: Self? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "CHESSCOM_OAUTH_CLIENT_ID") as? String,
              !clientID.isEmpty,
              let redirect = Bundle.main.object(forInfoDictionaryKey: "CHESSCOM_OAUTH_REDIRECT_URI") as? String,
              let redirectURI = URL(string: redirect) else { return nil }
        return Self(clientID: clientID, redirectURI: redirectURI)
    }
}

struct UnconfiguredChessComAuthorization: ChessComAccountAuthorizing {
    let isConfigured = false
    func authorize() async throws -> AuthorizedChessComAccount {
        throw APIError.unauthorized
    }
    func signOut() async {}
}
