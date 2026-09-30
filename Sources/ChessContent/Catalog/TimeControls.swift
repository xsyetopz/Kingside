import Foundation

/// `time-controls.json`: the offered clock presets and how they are grouped.
public struct TimeControlCatalog: Codable, Sendable {
  /// Moves assumed when estimating a game's length from its increment.
  public let estimatedMoves: Int
  /// In display order. A timed preset belongs to the first timed category it fits.
  public let categories: [TimeControlCategory]
  public let presets: [TimeControlPreset]

  public func preset(id: String) -> TimeControlPreset? { presets.first { $0.id == id } }

  /// Untimed presets go to the untimed category; timed ones by estimated game length.
  public func category(for preset: TimeControlPreset) -> TimeControlCategory? {
    let estimate = preset.initialSeconds + estimatedMoves * preset.incrementSeconds
    return categories.first { category in
      guard category.isTimed == preset.isTimed else { return false }
      guard let bound = category.belowEstimatedSeconds else { return true }
      return estimate < bound
    }
  }
}

public struct TimeControlCategory: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let nameKey: String
  /// SF Symbol name.
  public let symbol: String
  public let isTimed: Bool
  /// Upper bound (exclusive) of the estimated game length; nil for no bound.
  public let belowEstimatedSeconds: Int?
}

public struct TimeControlPreset: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  /// Zero means no clock.
  public let initialSeconds: Int
  public let incrementSeconds: Int
  public let labelKey: String

  public var isTimed: Bool { initialSeconds > 0 }

  /// PGN `TimeControl` tag value, such as `180+2`; `-` when untimed.
  public var pgnValue: String {
    guard isTimed else { return "-" }
    return incrementSeconds > 0 ? "\(initialSeconds)+\(incrementSeconds)" : "\(initialSeconds)"
  }
}
