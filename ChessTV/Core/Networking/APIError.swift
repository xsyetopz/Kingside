import Foundation

enum APIError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case offline
    case timedOut
    case unauthorized
    case notFound
    case rateLimited
    case server(Int)
    case invalidResponse
    case decoding
    case unsupported

    var errorDescription: String? {
        switch self {
        case .offline: "No internet connection. Your local games are still available."
        case .timedOut: "The request took too long. Please try again."
        case .notFound: "We couldn't find that player."
        case .rateLimited: "Too many requests. Please wait a moment and try again."
        case .unauthorized: "Account authorization is required."
        case .unsupported: "This service does not provide that information."
        default: "Unable to load this content right now."
        }
    }
}
