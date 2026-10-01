/// Runs requests strictly one at a time, in the order the owning actor calls `run`.
///
/// An actor owns the queue and calls `run` from its own isolation. Actor isolation alone would
/// interleave requests at each `await`, so the requests are chained explicitly.
public final class SerialRequestQueue {
  /// Completes when the most recently queued request has finished.
  private var tail: Task<Void, Never>?

  public init() {}

  // @preconcurrency would weaken Sendable checks for Swift 6 callers; this API has no older ones.
  // swiftlint:disable incompatible_concurrency_annotation
  /// Waits for every earlier request, then runs `operation`. A failed request does not stop the
  /// ones queued after it. Cancelling the caller cancels `operation`.
  nonisolated(nonsending) public func run<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let previous = tail
    let task = Task {
      await previous?.value
      return try await operation()
    }
    tail = Task { _ = await task.result }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
  // swiftlint:enable incompatible_concurrency_annotation
}

@available(*, unavailable)
extension SerialRequestQueue: Sendable {}
