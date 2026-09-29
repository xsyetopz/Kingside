import Foundation

/// Saved puzzle progress: rated puzzle rating and history, streak, Puzzle Rush bests,
/// seen puzzle ids and solved Daily Puzzle days.
struct PuzzleProgress: Codable, Equatable {
    var rating = PuzzleRating.initial
    /// Number of rated results recorded (drives the K-factor).
    var ratedPlayed = 0
    var streak = 0
    var bestStreak = 0
    /// Best score per `PuzzleRushMode.rawValue`.
    var rushBest: [String: Int] = [:]
    var seenIDs: Set<String> = []
    /// `PuzzleDay.key` values of solved Daily Puzzles.
    var dailySolved: Set<String> = []
}

/// Persists `PuzzleProgress` as JSON under one UserDefaults key.
@MainActor
final class PuzzleProgressStore: ObservableObject {
    @Published private(set) var progress: PuzzleProgress { didSet { save() } }
    private let defaults: UserDefaults
    private let key = "ChessTV.puzzleProgress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(PuzzleProgress.self, from: data) {
            progress = decoded
        } else {
            progress = PuzzleProgress()
        }
    }

    /// Applies a rated result and returns the rating change.
    @discardableResult
    func recordRated(puzzleRating: Int, solved: Bool) -> Int {
        let delta = PuzzleRating.change(
            rating: progress.rating, puzzleRating: puzzleRating, solved: solved, puzzlesPlayed: progress.ratedPlayed
        )
        progress.rating = max(100, progress.rating + delta)
        progress.ratedPlayed += 1
        recordStreak(solved: solved)
        return delta
    }

    /// Updates the streak without a rating change (unrated attempts).
    func recordStreak(solved: Bool) {
        progress.streak = solved ? progress.streak + 1 : 0
        progress.bestStreak = max(progress.bestStreak, progress.streak)
    }

    func markSeen(_ id: String) { progress.seenIDs.insert(id) }

    func resetSeen() { progress.seenIDs.removeAll() }

    func rushBest(for mode: PuzzleRushMode) -> Int { progress.rushBest[mode.rawValue] ?? 0 }

    /// Saves `score` if it beats the stored best; returns true for a new best.
    @discardableResult
    func recordRush(mode: PuzzleRushMode, score: Int) -> Bool {
        guard score > rushBest(for: mode) else { return false }
        progress.rushBest[mode.rawValue] = score
        return true
    }

    func isDailySolved(_ day: PuzzleDay) -> Bool { progress.dailySolved.contains(day.key) }

    func markDailySolved(_ day: PuzzleDay) { progress.dailySolved.insert(day.key) }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: key) }
    }
}
