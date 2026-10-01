/// How long to wait before reopening a Lichess stream. The wait starts at one second and doubles
/// after every disconnect up to 30 seconds; an event resets it.
public struct ReconnectPolicy: Sendable {
  private static let firstDelay: Duration = .seconds(1)
  private static let maxDelay: Duration = .seconds(30)
  /// Lichess asks clients to wait at least a minute after a 429.
  private static let rateLimitDelay: Duration = .seconds(60)

  private var delay = Self.firstDelay

  public init() {}

  /// An event arrived, so the connection works.
  public mutating func eventArrived() {
    delay = Self.firstDelay
  }

  /// Lichess answered 429, so the next wait is at least a minute.
  public mutating func rateLimited() {
    delay = max(delay, Self.rateLimitDelay)
  }

  /// The stream ended. Returns the wait before reconnecting, and doubles the one after it.
  public mutating func disconnected() -> Duration {
    let wait = delay
    delay = min(delay * 2, Self.maxDelay)
    return wait
  }
}
