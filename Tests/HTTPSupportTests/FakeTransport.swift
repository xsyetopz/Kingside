import Foundation
import HTTPSupport

/// The transport double for every client test: answers through `handler`, records each request,
/// serves NDJSON streams, and gives tests awaited barriers instead of timing.
public actor FakeTransport: HTTPStreamingTransport {
  /// Returns the status, headers, and body for a request, or throws as the transport would.
  public typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], Data)

  private enum Condition {
    case requestCount(Int)
    case request(String)
    case streamTerminated(String)
  }

  private typealias Continuation = CheckedContinuation<Void, Error>

  private struct Waiter {
    let id: UUID
    let condition: Condition
    let continuation: Continuation
  }

  private struct HeldRequest {
    let id: UUID
    let continuation: Continuation
  }

  /// Every request in arrival order, including requests still held.
  public private(set) var requests: [URLRequest] = []
  /// The most data requests that were ever between arrival and answer at once. Requests that
  /// are not held answer without suspending, so this shows overlap only after `holdRequests()`.
  public private(set) var maxConcurrency = 0
  private var inFlight = 0
  private var holdsRequests = false
  private var held: [HeldRequest] = []
  private var releaseCredits = 0
  private var openStreams: [String: AsyncThrowingStream<String, Error>.Continuation] = [:]
  /// The newest stream at each path, so that an older stream ending does not mark a newer one.
  private var currentStreams: [String: UUID] = [:]
  private var terminatedStreams: Set<String> = []
  private var waiters: [Waiter] = []
  private let handler: Handler
  private let streamLines: [String]
  private let keepStreamsOpen: Bool

  /// Each stream yields `streamLines`, then ends unless `keepStreamsOpen` is set; an open stream
  /// takes more lines from `push(_:to:)` and ends with `finishStream(_:)`.
  public init(
    streamLines: [String] = [],
    keepStreamsOpen: Bool = false,
    handler: @escaping Handler
  ) {
    self.handler = handler
    self.streamLines = streamLines
    self.keepStreamsOpen = keepStreamsOpen
  }

  /// Each request as "METHOD /path", in arrival order.
  public var paths: [String] { requests.map(Self.methodAndPath) }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    inFlight += 1
    defer { inFlight -= 1 }
    maxConcurrency = max(maxConcurrency, inFlight)
    record(request)
    if holdsRequests { try await waitForRelease() }
    let (status, headers, body) = try handler(request)
    return (body, Self.response(to: request, status: status, headers: headers))
  }

  public func lines(
    for request: URLRequest
  ) throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
    let path = request.url!.path()
    let status: Int
    let headers: [String: String]
    do {
      (status, headers, _) = try handler(request)
    } catch {
      record(request)
      throw error
    }
    let id = UUID()
    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    continuation.onTermination = { _ in Task { await self.markTerminated(path, id: id) } }
    currentStreams[path] = id
    terminatedStreams.remove(path)
    for line in streamLines { continuation.yield(line) }
    if keepStreamsOpen { openStreams[path] = continuation } else { continuation.finish() }
    // Recorded after the stream exists, so a test that waits for the request can push at once.
    record(request)
    return (Self.response(to: request, status: status, headers: headers), stream)
  }

  // MARK: - Barriers

  /// Makes each later data request wait at the transport until `releaseHeldRequest()`.
  public func holdRequests() { holdsRequests = true }

  /// Lets the oldest held request answer, or the next one to arrive if none is held.
  public func releaseHeldRequest() {
    if held.isEmpty {
      releaseCredits += 1
    } else {
      held.removeFirst().continuation.resume()
    }
  }

  /// Returns once `count` requests have arrived. A cancelled test throws.
  public func waitForRequests(count: Int) async throws {
    try await wait(for: .requestCount(count))
  }

  /// Returns once a request "METHOD /path" has arrived. A cancelled test throws.
  public func waitForRequest(_ methodAndPath: String) async throws {
    try await wait(for: .request(methodAndPath))
  }

  /// Returns once the stream at `path` has finished or lost its consumer. A cancelled test throws.
  public func waitForStreamTermination(_ path: String) async throws {
    try await wait(for: .streamTerminated(path))
  }

  // MARK: - Open streams

  public func push(_ line: String, to path: String) { openStreams[path]?.yield(line) }

  /// Ends the stream at `path`, as the server does.
  public func finishStream(_ path: String) { openStreams[path]?.finish() }

  // MARK: - Private

  private static func methodAndPath(_ request: URLRequest) -> String {
    (request.httpMethod ?? "GET") + " " + request.url!.path()
  }

  private static func response(
    to request: URLRequest,
    status: Int,
    headers: [String: String]
  ) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
  }

  private func record(_ request: URLRequest) {
    requests.append(request)
    resumeMetWaiters()
  }

  private func markTerminated(_ path: String, id: UUID) {
    guard currentStreams[path] == id else { return }
    terminatedStreams.insert(path)
    resumeMetWaiters()
  }

  private func waitForRelease() async throws {
    if releaseCredits > 0 {
      releaseCredits -= 1
      return
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: Continuation) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          held.append(HeldRequest(id: id, continuation: continuation))
        }
      }
    } onCancel: {
      Task { await self.cancelHeldRequest(id) }
    }
  }

  private func cancelHeldRequest(_ id: UUID) {
    guard let index = held.firstIndex(where: { $0.id == id }) else { return }
    held.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  private func isMet(_ condition: Condition) -> Bool {
    switch condition {
    case .requestCount(let count): requests.count >= count
    case .request(let methodAndPath): paths.contains(methodAndPath)
    case .streamTerminated(let path): terminatedStreams.contains(path)
    }
  }

  private func wait(for condition: Condition) async throws {
    if isMet(condition) { return }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: Continuation) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters.append(Waiter(id: id, condition: condition, continuation: continuation))
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  private func cancelWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  private func resumeMetWaiters() {
    let met = waiters.filter { isMet($0.condition) }
    waiters.removeAll { isMet($0.condition) }
    for waiter in met { waiter.continuation.resume() }
  }
}
