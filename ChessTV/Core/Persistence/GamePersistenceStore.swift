import Foundation
import ChessCore

struct SavedLocalGame: Codable, Identifiable, Equatable {
    let id: UUID
    var game: ChessGame
    var humanColor: PieceColor
    var difficulty: EngineDifficulty
    var whiteTime: TimeInterval
    var blackTime: TimeInterval
    var initialTime: TimeInterval
    var increment: TimeInterval
    var updatedAt: Date
    var isFinished: Bool
}

actor GamePersistenceStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        let base = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("ChessTV", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("games.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func allGames() -> [SavedLocalGame] {
        guard let data = try? Data(contentsOf: fileURL),
              let games = try? decoder.decode([SavedLocalGame].self, from: data) else { return [] }
        return games.sorted { $0.updatedAt > $1.updatedAt }
    }

    func unfinishedGame() -> SavedLocalGame? { allGames().first { !$0.isFinished } }

    func save(_ game: SavedLocalGame) throws {
        var games = allGames()
        games.removeAll { $0.id == game.id }
        games.append(game)
        let retainedGames = Array(games.sorted { $0.updatedAt > $1.updatedAt }.prefix(50))
        let data = try encoder.encode(retainedGames)
        try data.write(to: fileURL, options: .atomic)
    }
}
