import Foundation

/// The network port of an API client.
public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Thrown by `URLSessionTransport`. Each client maps it to its own error type.
public enum HTTPTransportError: Error, Equatable, Sendable {
  /// The response was not an HTTP response.
  case invalidResponse
}

public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw HTTPTransportError.invalidResponse
    }
    return (data, http)
  }
}
