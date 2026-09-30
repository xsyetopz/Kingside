import Foundation

/// Read-only client for the Chess.com Published-Data API. Requests run strictly one at a time.
public actor ChessComClient {
  private let configuration: ChessComConfiguration
  private let transport: any HTTPTransport
  private var cache: any ResponseCache
  /// Completes when the most recently queued request has finished.
  private var tail: Task<Void, Never>?

  public init(
    configuration: ChessComConfiguration,
    transport: any HTTPTransport = URLSessionTransport(),
    cache: any ResponseCache = InMemoryResponseCache()
  ) {
    self.configuration = configuration
    self.transport = transport
    self.cache = cache
  }

  public func profile(username: String) async throws -> ChessComProfile {
    try decode(ChessComProfile.self, from: try await get(playerURL(username)))
  }

  public func stats(username: String) async throws -> ChessComStats {
    try decode(
      ChessComStats.self,
      from: try await get(playerURL(username).appending(path: "stats"))
    )
  }

  public func archives(username: String) async throws -> [URL] {
    let url = try playerURL(username).appending(path: "games").appending(path: "archives")
    return try decode(ChessComArchivesResponse.self, from: try await get(url)).archives
  }

  public func games(username: String, year: Int, month: Int) async throws -> [ChessComGame] {
    guard (1...9999).contains(year), (1...12).contains(month) else {
      throw ChessComError.invalidArchive
    }
    let url = try playerURL(username).appending(path: "games")
      .appending(path: String(format: "%04d", year))
      .appending(path: String(format: "%02d", month))
    return try decode(ChessComGamesResponse.self, from: try await get(url)).games
  }

  /// `archiveURL` is one of the URLs returned by `archives(username:)`; other hosts are rejected.
  public func games(archiveURL: URL) async throws -> [ChessComGame] {
    let base = configuration.baseURL
    guard archiveURL.scheme == base.scheme,
      archiveURL.host() == base.host(),
      archiveURL.port == base.port,
      archiveURL.path().hasPrefix(base.path())
    else { throw ChessComError.invalidArchive }
    return try decode(ChessComGamesResponse.self, from: try await get(archiveURL)).games
  }

  private func playerURL(_ username: String) throws -> URL {
    let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard (3...25).contains(name.count),
      name.utf8.allSatisfy({
        ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x5F || $0 == 0x2D
      })
    else { throw ChessComError.invalidUsername }
    return configuration.baseURL.appending(path: "player").appending(path: name)
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw ChessComError.decoding(String(describing: error))
    }
  }

  /// Queues behind every earlier request. Actor isolation alone would interleave requests
  /// at each `await`, so the requests are chained explicitly.
  private func get(_ url: URL) async throws -> Data {
    let previous = tail
    let task = Task {
      await previous?.value
      return try await fetch(url)
    }
    tail = Task { _ = await task.result }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let cached = cache.response(for: url)
    if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

    let (data, response) = try await transport.data(for: request)
    switch response.statusCode {
    case 200..<300:
      if let etag = response.value(forHTTPHeaderField: "ETag") {
        cache.store(CachedResponse(etag: etag, body: data), for: url)
      }
      return data
    case 304:
      guard let cached else { throw ChessComError.http(status: 304) }
      return cached.body
    case 404:
      throw ChessComError.notFound
    case 429:
      throw ChessComError.rateLimited(
        retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
      )
    default:
      throw ChessComError.http(status: response.statusCode)
    }
  }
}
