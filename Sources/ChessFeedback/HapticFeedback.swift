import ChessContent
import CoreHaptics

/// Plays the Core Haptics patterns of `FeedbackTuning.haptics`.
///
/// It does nothing on hardware without haptics, which includes every Mac and Apple TV.
@preconcurrency
@MainActor
public final class HapticFeedback {
  public var isEnabled: Bool

  private let engine: CHHapticEngine?
  private var patterns: [HapticEventID: CHHapticPattern] = [:]
  private var needsStart = true

  /// Whether this hardware can play haptics. A capability check, not a device check.
  public static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

  public init(haptics: [HapticEventID: HapticPattern], isEnabled: Bool = true) {
    self.isEnabled = isEnabled
    guard Self.isSupported, let engine = try? CHHapticEngine() else {
      engine = nil
      return
    }
    self.engine = engine
    engine.playsHapticsOnly = true
    engine.stoppedHandler = { [weak self] _ in
      Task { @MainActor in self?.needsStart = true }
    }
    engine.resetHandler = { [weak self] in
      Task { @MainActor in self?.needsStart = true }
    }
    patterns = haptics.compactMapValues { try? Self.pattern($0) }
  }

  public func play(_ haptic: HapticEventID) {
    guard isEnabled, let engine, let pattern = patterns[haptic] else { return }
    do {
      if needsStart {
        try engine.start()
        needsStart = false
      }
      try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    } catch {
      needsStart = true
    }
  }

  static func pattern(_ pattern: HapticPattern) throws -> CHHapticPattern {
    let events = pattern.pulses.map { pulse in
      let parameters = [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(pulse.intensity)),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(pulse.sharpness)),
      ]
      return pulse.duration > 0
        ? CHHapticEvent(
          eventType: .hapticContinuous,
          parameters: parameters,
          relativeTime: pulse.time,
          duration: pulse.duration
        )
        : CHHapticEvent(
          eventType: .hapticTransient,
          parameters: parameters,
          relativeTime: pulse.time
        )
    }
    return try CHHapticPattern(events: events, parameters: [])
  }
}
