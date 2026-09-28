import XCTest
import ChessCore
@testable import ChessTV

final class PersistenceTests: XCTestCase {
    func testSavedGameRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = GamePersistenceStore(directoryURL: directory)
        var game = ChessGame()
        try game.makeMove(XCTUnwrap(ChessMove(uci: "e2e4")))
        let saved = SavedLocalGame(
            id: UUID(), game: game, humanColor: .white, difficulty: .easy,
            whiteTime: 299, blackTime: 300, initialTime: 300, increment: 0,
            updatedAt: Date(), isFinished: false
        )
        try await store.save(saved)
        let restored = await store.unfinishedGame()
        XCTAssertEqual(restored?.game.position, game.position)
        XCTAssertEqual(restored?.whiteTime, 299)
    }

    @MainActor
    func testSettingsRoundTrip() {
        let suite = "ChessTVTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        first.value.showCoordinates = false
        first.value.engineDifficulty = .hard
        let second = SettingsStore(defaults: defaults)
        XCTAssertFalse(second.value.showCoordinates)
        XCTAssertEqual(second.value.engineDifficulty, .hard)
    }
}
