import Foundation

/// Pure puzzle picking for rated play, Puzzle Rush and the Daily Puzzle.
enum PuzzleSelector {
    static let ratedWindow = 200

    /// A random unseen puzzle within ±`window` of `rating`, else the closest unseen one.
    /// Returns nil when every puzzle has been seen (the caller resets its seen list).
    static func rated<G: RandomNumberGenerator>(
        from puzzles: [Puzzle],
        rating: Int,
        seen: Set<String>,
        window: Int = ratedWindow,
        using generator: inout G
    ) -> Puzzle? {
        let unseen = puzzles.filter { !seen.contains($0.id) }
        let nearby = unseen.filter { abs($0.rating - rating) <= window }
        if let pick = nearby.randomElement(using: &generator) { return pick }
        return unseen.min { abs($0.rating - rating) < abs($1.rating - rating) }
    }

    /// Target rating of the `index`-th puzzle (0-based) in a Puzzle Rush run.
    static func rushTargetRating(index: Int) -> Int {
        min(2700, 400 + 50 * index)
    }

    /// A puzzle for position `index` of a rush run, escalating from about 400.
    static func rush<G: RandomNumberGenerator>(
        from puzzles: [Puzzle],
        index: Int,
        excluding used: Set<String>,
        using generator: inout G
    ) -> Puzzle? {
        rated(from: puzzles, rating: rushTargetRating(index: index), seen: used, window: 75, using: &generator)
    }

    /// Rating range the Daily Puzzle is drawn from.
    static let dailyRatings = 1200...2000

    /// Deterministic puzzle for a calendar day; the same day always gives the same puzzle.
    static func daily(from puzzles: [Puzzle], day: PuzzleDay) -> Puzzle? {
        let pool = puzzles.filter { dailyRatings.contains($0.rating) }.sorted { $0.id < $1.id }
        guard !pool.isEmpty else { return nil }
        // Multiplying by a large prime walks the pool in a scrambled order, one step per day.
        let step = (day.dayNumber * 7_919) % pool.count
        return pool[(step + pool.count) % pool.count]
    }
}

/// A calendar day in the user's calendar, used as the Daily Puzzle key.
struct PuzzleDay: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// "2026-09-29"; the key stored for solved days.
    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Hinnant's days_from_civil).
    var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
