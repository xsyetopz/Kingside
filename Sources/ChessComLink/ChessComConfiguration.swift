import Foundation

/// Values the caller injects into `ChessComClient`; the client hard-codes neither.
public struct ChessComConfiguration: Sendable, Equatable {
    /// PubAPI root, for example the `pub/` URL of the Chess.com API host.
    public var baseURL: URL
    /// Sent as `User-Agent`; Chess.com asks that it includes contact information.
    public var userAgent: String

    public init(baseURL: URL, userAgent: String) {
        self.baseURL = baseURL
        self.userAgent = userAgent
    }
}

public enum ChessComError: Error, Equatable, Sendable {
    case invalidUsername
    case invalidArchive
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int)
    case invalidResponse
    case decoding(String)
}
