import CryptoKit
import Foundation
import Security

/// Authorization-code flow with PKCE (S256 only) for the Lichess OAuth endpoints.
public struct LichessOAuth: Sendable {
    public static let scope = "board:play challenge:read challenge:write"

    private let configuration: LichessConfiguration
    private let transport: any LichessTransport

    public init(configuration: LichessConfiguration, transport: any LichessTransport = URLSessionLichessTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// A random base64url code verifier of 43 characters (32 random bytes).
    public static func makeVerifier() throws -> String {
        try randomToken()
    }

    /// A random base64url value for the `state` parameter.
    public static func makeState() throws -> String {
        try randomToken()
    }

    /// `base64url(SHA256(verifier))` without padding.
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public func authorizeURL(state: String, challenge: String) -> URL {
        var components = URLComponents(url: configuration.baseURL.appending(path: "oauth"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Trades the authorization code for an access token.
    public func exchange(code: String, verifier: String) async throws -> String {
        struct TokenResponse: Decodable { var access_token: String }
        var request = URLRequest(url: configuration.baseURL.appending(path: "api/token"))
        request.httpMethod = "POST"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = LichessForm.encode([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", configuration.redirectURI.absoluteString),
            ("client_id", configuration.clientID),
        ])
        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 200..<300: break
        case 429: throw LichessError.rateLimited
        default: throw LichessError.http(status: response.statusCode)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
        } catch {
            throw LichessError.decoding(String(describing: error))
        }
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw LichessError.invalidResponse }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
