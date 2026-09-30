import Foundation

/// Endpoints of outside services, decoded from `services.json`.
public struct ServiceEndpoints: Codable, Hashable, Sendable {
    public let chessCom: ChessComEndpoints
}

/// The Chess.com Published-Data API and the contact that goes into its `User-Agent`.
public struct ChessComEndpoints: Codable, Hashable, Sendable {
    public let baseURL: URL
    /// A member page; `{username}` is replaced with the linked username.
    public let profileURLTemplate: String
    /// Chess.com asks API clients to name a contact in the `User-Agent`.
    public let contactURL: URL

    public func profileURL(username: String) -> URL? {
        URL(string: profileURLTemplate.replacingOccurrences(of: "{username}", with: username))
    }

    /// `<product>/<version> (+<contact>)`.
    public func userAgent(product: String, version: String) -> String {
        "\(product)/\(version) (+\(contactURL.absoluteString))"
    }
}
