import Foundation

/// The network port of an API client.
public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// A transport that can also hold a response open and read it line by line.
public protocol HTTPStreamingTransport: HTTPTransport {
  /// Opens an NDJSON stream. The response arrives once the headers do; `lines` then yields
  /// one element per line and ends when the server closes the connection.
  func lines(
    for request: URLRequest
  ) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
}

/// Thrown by `URLSessionTransport`. Each client maps it to its own error type.
public enum HTTPTransportError: Error, Equatable, Sendable {
  /// The response was not an HTTP response.
  case invalidResponse
}

public struct URLSessionTransport: HTTPStreamingTransport {
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

  public func lines(
    for request: URLRequest
  ) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw HTTPTransportError.invalidResponse
    }
    let stream = AsyncThrowingStream<String, Error> { continuation in
      // Cancelling the task that iterates `bytes` cancels the underlying URLSession task.
      let task = Task {
        do {
          for try await line in bytes.lines { continuation.yield(line) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
    return (http, stream)
  }
}
