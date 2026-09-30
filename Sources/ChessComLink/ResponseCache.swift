import Foundation

public struct CachedResponse: Sendable, Equatable {
    public var etag: String
    public var body: Data

    public init(etag: String, body: Data) {
        self.etag = etag
        self.body = body
    }
}

/// Remembers the last body per URL so a `304 Not Modified` can be answered locally.
/// A disk-backed type can replace `InMemoryResponseCache`.
public protocol ResponseCache: Sendable {
    func response(for url: URL) -> CachedResponse?
    mutating func store(_ response: CachedResponse, for url: URL)
}

public struct InMemoryResponseCache: ResponseCache {
    private var entries: [URL: CachedResponse] = [:]

    public init() {}

    public func response(for url: URL) -> CachedResponse? {
        entries[url]
    }

    public mutating func store(_ response: CachedResponse, for url: URL) {
        entries[url] = response
    }
}
