import ChessCore
import Foundation

/// Stores local games as one JSON file, by default `Kingside/saved-games.json` in
/// Application Support. It is the only writer of that file on a device.
/// - At most one game is unfinished: saving an ongoing game drops any other ongoing game.
/// - Finished games form the archive; only the newest `archiveLimit` are kept.
/// - `allGames()` is sorted newest first by `updatedAt`.
/// - Writes replace the file atomically, so a crash during a write keeps the old archive.
/// - A file that exists but does not decode is never overwritten; reads and writes throw.
/// - The file is decoded once, on the first successful read, and a missing file is kept as an
///   empty archive; later changes to the file from outside the store are not seen.
public actor GamePersistenceStore {
  static let archiveLimit = 200
  /// Only a name: no build has shipped another format, so nothing reads or migrates older files.
  public static let fileName = "saved-games.json"

  public let fileURL: URL
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  /// Newest first. Nil until the file reads, so an unreadable file is read again on each access.
  private var games: [SavedGame]?

  /// `fileURL` is the archive file; its directory is created on the first write.
  public init(fileURL: URL) {
    self.fileURL = fileURL
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  /// `Kingside/saved-games.json` in the user's Application Support directory.
  public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
    try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appending(components: "Kingside", fileName)
  }

  /// Empty when the file does not exist yet. Throws when it exists but cannot be read or
  /// decoded, so `save` and `delete` never replace an archive they could not read.
  public func allGames() throws -> [SavedGame] {
    if let games { return games }
    let loaded: [SavedGame]
    do {
      loaded = try decoder.decode([SavedGame].self, from: Data(contentsOf: fileURL))
    } catch CocoaError.fileReadNoSuchFile {
      loaded = []
    }
    let sorted = loaded.sorted { $0.updatedAt > $1.updatedAt }
    games = sorted
    return sorted
  }

  /// The game to offer on Resume, if any.
  public func unfinishedGame() throws -> SavedGame? { try allGames().first { !$0.isFinished } }

  /// Inserts or replaces `game` by id.
  public func save(_ game: SavedGame) throws {
    var updated = try allGames().filter { $0.id != game.id }
    if !game.isFinished { updated.removeAll { !$0.isFinished } }
    updated.append(game)
    try write(updated)
  }

  public func delete(id: UUID) throws {
    try write(try allGames().filter { $0.id != id })
  }

  /// Memory changes only after the file is written, so a failed write leaves both unchanged.
  private func write(_ updated: [SavedGame]) throws {
    let sorted = updated.sorted { $0.updatedAt > $1.updatedAt }
    let unfinished = sorted.filter { !$0.isFinished }
    let finished = sorted.filter(\.isFinished).prefix(Self.archiveLimit)
    let kept = unfinished + finished
    let data = try encoder.encode(kept)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
    games = kept.sorted { $0.updatedAt > $1.updatedAt }
  }
}
