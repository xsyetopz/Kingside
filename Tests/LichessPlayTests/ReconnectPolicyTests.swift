import LichessPlay
import Testing

struct ReconnectPolicyTests {
  private func waits(_ count: Int, _ policy: inout ReconnectPolicy) -> [Duration] {
    (0..<count).map { _ in policy.disconnected() }
  }

  @Test
  func waitDoublesFromOneSecondUpToThirtySeconds() {
    var policy = ReconnectPolicy()
    #expect(
      waits(8, &policy) == [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) }
    )
  }

  @Test
  func anEventResetsTheWaitToOneSecond() {
    var policy = ReconnectPolicy()
    _ = waits(4, &policy)
    policy.eventArrived()
    #expect(waits(2, &policy) == [.seconds(1), .seconds(2)])
  }

  @Test
  func aRateLimitWaitsAtLeastAMinute() {
    var policy = ReconnectPolicy()
    policy.rateLimited()
    #expect(policy.disconnected() == .seconds(60))
  }

  @Test
  func theWaitAfterARateLimitedOneIsCapped() {
    var policy = ReconnectPolicy()
    _ = waits(2, &policy)
    policy.rateLimited()
    #expect(waits(2, &policy) == [.seconds(60), .seconds(30)])
  }
}
