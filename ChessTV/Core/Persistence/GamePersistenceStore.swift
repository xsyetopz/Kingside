import Foundation
import ChessCore

/// Stores local games as one JSON file (`saved-games-v2.json`) in Application Support.
/// - At most one game is unfinished: saving an ongoing game drops any other ongoing game.
/// - Finished games form the archive; only the newest `archiveLimit` are kept.
/// - `allGames()` is sorted newest first by `updatedAt`.
actor GamePersistenceStore {
    static let archiveLimit = 200

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        let base = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("ChessTV", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("saved-games-v2.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func allGames() -> [SavedGame] {
        guard let data = try? Data(contentsOf: fileURL),
              let games = try? decoder.decode([SavedGame].self, from: data) else { return [] }
        return games.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The game to offer on Resume, if any.
    func unfinishedGame() -> SavedGame? { allGames().first { !$0.isFinished } }

    /// Inserts or replaces `game` by id.
    func save(_ game: SavedGame) throws {
        var games = allGames().filter { $0.id != game.id }
        if !game.isFinished { games.removeAll { !$0.isFinished } }
        games.append(game)
        try write(games)
    }

    func delete(id: UUID) throws {
        try write(allGames().filter { $0.id != id })
    }

    private func write(_ games: [SavedGame]) throws {
        let sorted = games.sorted { $0.updatedAt > $1.updatedAt }
        let unfinished = sorted.filter { !$0.isFinished }
        let finished = sorted.filter(\.isFinished).prefix(Self.archiveLimit)
        let data = try encoder.encode(unfinished + finished)
        try data.write(to: fileURL, options: .atomic)
    }
}
