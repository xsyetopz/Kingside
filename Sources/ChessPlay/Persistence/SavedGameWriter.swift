import ChessCore
import Foundation

/// Builds the `SavedGame` of a session and writes it, one save at a time.
@MainActor
final class SavedGameWriter {
  typealias Write = @Sendable (SavedGame) async throws -> Void

  private let write: Write
  private let onSave: @MainActor () -> Void
  private let onFailure: @MainActor (UUID) -> Void
  /// The latest save; each save waits for the previous one, so the newest snapshot wins.
  private var lastSave: Task<Void, Never>?

  /// `onSave` runs after each successful save; `onFailure` runs after each failed save, with the
  /// ID of the game whose save failed.
  convenience init(
    store: GamePersistenceStore,
    onSave: @escaping @MainActor () -> Void,
    onFailure: @escaping @MainActor (UUID) -> Void
  ) {
    self.init(write: { try await store.save($0) }, onSave: onSave, onFailure: onFailure)
  }

  init(
    write: @escaping Write,
    onSave: @escaping @MainActor () -> Void,
    onFailure: @escaping @MainActor (UUID) -> Void
  ) {
    self.write = write
    self.onSave = onSave
    self.onFailure = onFailure
  }

  /// Saves after the previous save finished; `updatedAt` is the time of this call.
  func save(
    id: UUID,
    createdAt: Date,
    mode: GameMode,
    white: PlayerInfo,
    black: PlayerInfo,
    timeControl: TimeControl,
    autoFlip: Bool,
    game: ChessGame,
    result: GameResult,
    termination: GameTermination?,
    clock: GameClock
  ) {
    let snapshot = SavedGame(
      id: id,
      createdAt: createdAt,
      updatedAt: Date(),
      mode: mode,
      white: white,
      black: black,
      timeControl: timeControl,
      autoFlip: autoFlip,
      game: game,
      result: result,
      termination: termination,
      clock: clock
    )
    let previous = lastSave
    lastSave = Task { [weak self, write] in
      await previous?.value
      do {
        try await write(snapshot)
        self?.onSave()
      } catch {
        self?.onFailure(snapshot.id)
      }
    }
  }

  /// Returns once every save started so far has finished.
  func flush() async {
    await lastSave?.value
  }
}
