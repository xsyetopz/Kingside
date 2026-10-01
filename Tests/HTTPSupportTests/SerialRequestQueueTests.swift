import Testing

import HTTPSupport

/// Records events in order and lets a test wait until an event has happened.
private actor EventLog {
  private(set) var events: [String] = []
  private var waiters: [(event: String, continuation: CheckedContinuation<Void, Never>)] = []

  func record(_ event: String) {
    events.append(event)
    for waiter in waiters where waiter.event == event { waiter.continuation.resume() }
    waiters.removeAll { $0.event == event }
  }

  func waitFor(_ event: String) async {
    if events.contains(event) { return }
    await withCheckedContinuation { waiters.append((event, $0)) }
  }
}

/// A gate that holds a request until the test opens it.
private actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }

  func pass() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

private struct RequestFailed: Error, Equatable {}

/// Owns a queue the way an API client does.
private actor Client {
  private let queue = SerialRequestQueue()
  private var queued: Set<Int> = []
  private var waiters: [(id: Int, continuation: CheckedContinuation<Void, Never>)] = []

  /// Marks `id` as queued in the same actor turn that queues the request, so a waiter resumes
  /// only after the request is in the queue.
  func request<Value: Sendable>(
    _ id: Int,
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    queued.insert(id)
    for waiter in waiters where waiter.id == id { waiter.continuation.resume() }
    waiters.removeAll { $0.id == id }
    return try await queue.run(operation)
  }

  func waitUntilQueued(_ id: Int) async {
    if queued.contains(id) { return }
    await withCheckedContinuation { waiters.append((id, $0)) }
  }
}

@Suite
struct SerialRequestQueueTests {
  @Test
  func secondRequestStartsOnlyAfterTheFirstFinishes() async throws {
    let log = EventLog()
    let gate = Gate()
    let client = Client()
    let first = Task {
      try await client.request(1) {
        await log.record("start 1")
        await gate.pass()
        await log.record("end 1")
      }
    }
    await log.waitFor("start 1")
    let second = Task {
      try await client.request(2) { await log.record("start 2") }
    }
    await client.waitUntilQueued(2)
    await gate.open()
    try await first.value
    try await second.value
    #expect(await log.events == ["start 1", "end 1", "start 2"])
  }

  @Test
  func queuedRequestsStartInCallOrderOneAtATime() async throws {
    let log = EventLog()
    let gate = Gate()
    let client = Client()
    let first = Task {
      try await client.request(1) {
        await log.record("start 1")
        await gate.pass()
        await log.record("end 1")
      }
    }
    await log.waitFor("start 1")
    var queued: [Task<Void, any Error>] = []
    for id in 2...4 {
      let request = Task {
        try await client.request(id) {
          await log.record("start \(id)")
          await Task.yield()
          await log.record("end \(id)")
        }
      }
      queued.append(request)
      await client.waitUntilQueued(id)
    }
    await gate.open()
    try await first.value
    for request in queued { try await request.value }
    #expect(
      await log.events == [
        "start 1", "end 1", "start 2", "end 2", "start 3", "end 3", "start 4", "end 4",
      ]
    )
  }

  @Test
  func cancellingAQueuedRequestLeavesTheLaterOneQueued() async throws {
    let log = EventLog()
    let gate = Gate()
    let client = Client()
    let first = Task {
      try await client.request(1) {
        await log.record("start 1")
        await gate.pass()
        await log.record("end 1")
      }
    }
    await log.waitFor("start 1")
    let second = Task {
      try await client.request(2) {
        try Task.checkCancellation()
        await log.record("start 2")
      }
    }
    await client.waitUntilQueued(2)
    let third = Task {
      try await client.request(3) {
        await log.record(Task.isCancelled ? "start 3 cancelled" : "start 3")
      }
    }
    await client.waitUntilQueued(3)
    second.cancel()
    await gate.open()
    try await first.value
    await #expect(throws: CancellationError.self) { try await second.value }
    try await third.value
    #expect(await log.events == ["start 1", "end 1", "start 3"])
  }

  @Test
  func failedRequestDoesNotBlockTheNext() async throws {
    let client = Client()
    let first = Task { try await client.request(1) { () -> Int in throw RequestFailed() } }
    await client.waitUntilQueued(1)
    let second = Task { try await client.request(2) { 7 } }
    await #expect(throws: RequestFailed()) { try await first.value }
    #expect(try await second.value == 7)
  }
}
