import ChessContent
import Foundation

/// Pure puzzle picking for rated play, Puzzle Rush, and the Daily Puzzle.
public struct PuzzleSelector: Sendable {
  public let tuning: PuzzleSelectionTuning

  /// `tuning` is `ContentCatalog.tuning.puzzleSelection`.
  public init(tuning: PuzzleSelectionTuning) {
    self.tuning = tuning
  }

  /// A random unseen puzzle within ±`window` (default `ratedWindow`) of `rating`, else the
  /// closest unseen one. Returns nil when every puzzle has been seen (the caller resets its
  /// seen list).
  public func rated<G: RandomNumberGenerator>(
    from puzzles: [Puzzle],
    rating: Int,
    seen: Set<String>,
    window: Int? = nil,
    using generator: inout G
  ) -> Puzzle? {
    let window = window ?? tuning.ratedWindow
    let unseen = puzzles.filter { !seen.contains($0.id) }
    let nearby = unseen.filter { abs($0.rating - rating) <= window }
    if let pick = nearby.randomElement(using: &generator) { return pick }
    return unseen.min { abs($0.rating - rating) < abs($1.rating - rating) }
  }

  /// Target rating of the `index`-th puzzle (0-based) in a Puzzle Rush run.
  public func rushTargetRating(index: Int) -> Int {
    min(tuning.rushMaximumRating, tuning.rushStartRating + tuning.rushRatingStep * index)
  }

  /// A puzzle for position `index` of a rush run, escalating from `rushStartRating`.
  public func rush<G: RandomNumberGenerator>(
    from puzzles: [Puzzle],
    index: Int,
    excluding used: Set<String>,
    using generator: inout G
  ) -> Puzzle? {
    rated(
      from: puzzles,
      rating: rushTargetRating(index: index),
      seen: used,
      window: tuning.rushWindow,
      using: &generator
    )
  }

  /// Rating range the Daily Puzzle is drawn from.
  public var dailyRatings: ClosedRange<Int> {
    tuning.dailyMinimumRating...tuning.dailyMaximumRating
  }

  /// Deterministic puzzle for a calendar day; the same day always gives the same puzzle.
  public func daily(from puzzles: [Puzzle], day: PuzzleDay) -> Puzzle? {
    let pool = puzzles.filter { dailyRatings.contains($0.rating) }.sorted { $0.id < $1.id }
    guard !pool.isEmpty else { return nil }
    // Multiplying by a large prime walks the pool in a scrambled order, one step per day.
    let step = (day.dayNumber * 7_919) % pool.count
    return pool[(step + pool.count) % pool.count]
  }
}

/// A calendar day in the user's calendar, used as the Daily Puzzle key.
public struct PuzzleDay: Hashable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// `date` is the caller's injected "now"; `calendar` defaults to the user's calendar.
  public init(date: Date, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
  }

  /// "2026-09-29"; the key stored for solved days.
  public var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

  /// Days since 1970-01-01 in the proleptic Gregorian calendar (Hinnant's days_from_civil).
  public var dayNumber: Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }
}
