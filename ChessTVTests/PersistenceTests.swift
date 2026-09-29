import XCTest
import ChessCore
@testable import ChessTV

final class PersistenceTests: XCTestCase {
    private func makeStore() -> GamePersistenceStore {
        GamePersistenceStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func makeGame(
        result: GameResult = .ongoing,
        // Whole seconds: the store encodes dates as ISO 8601, which drops fractions.
        updatedAt: Date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
        moves: [String] = ["e2e4"]
    ) throws -> SavedGame {
        var game = ChessGame()
        for uci in moves { try game.makeMove(XCTUnwrap(ChessMove(uci: uci))) }
        var clock = GameClock(timeControl: TimeControl(initialSeconds: 180, incrementSeconds: 2))
        clock.consume(12.5, by: .white)
        return SavedGame(
            id: UUID(), createdAt: updatedAt, updatedAt: updatedAt, mode: .bot(id: BotRoster.defaultBot.id),
            white: PlayerInfo(name: "You"), black: BotRoster.defaultBot.playerInfo,
            timeControl: clock.timeControl, autoFlip: false, game: game, result: result,
            termination: result == .ongoing ? nil : .resignation, clock: clock
        )
    }

    func testUnfinishedGameRoundTrip() async throws {
        let store = makeStore()
        let saved = try makeGame()
        try await store.save(saved)
        let restored = await store.unfinishedGame()
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored?.clock.remaining(.white), 167.5)
        XCTAssertEqual(restored?.humanColor, .white)
    }

    func testSavingOngoingGameReplacesOtherOngoingGame() async throws {
        let store = makeStore()
        let first = try makeGame(updatedAt: Date(timeIntervalSince1970: 100))
        let second = try makeGame(updatedAt: Date(timeIntervalSince1970: 200))
        try await store.save(first)
        try await store.save(second)
        let all = await store.allGames()
        XCTAssertEqual(all.map(\.id), [second.id])
    }

    func testFinishedGamesAreKeptAndNotOfferedForResume() async throws {
        let store = makeStore()
        var game = try makeGame()
        try await store.save(game)
        game.result = .blackWon
        game.termination = .resignation
        try await store.save(game)
        let unfinished = await store.unfinishedGame()
        let all = await store.allGames()
        XCTAssertNil(unfinished)
        XCTAssertEqual(all.map(\.result), [.blackWon])
    }

    func testDelete() async throws {
        let store = makeStore()
        let game = try makeGame(result: .draw)
        try await store.save(game)
        try await store.delete(id: game.id)
        let all = await store.allGames()
        XCTAssertTrue(all.isEmpty)
    }

    func testPGNHasTagsAndResult() throws {
        let pgn = try makeGame(result: .blackWon).pgn
        XCTAssertTrue(pgn.contains("[White \"You\"]"))
        XCTAssertTrue(pgn.contains("[TimeControl \"180+2\"]"))
        XCTAssertTrue(pgn.contains("[Termination \"\(BotRoster.defaultBot.name) won by resignation\"]"))
        XCTAssertTrue(pgn.contains("1. e4"))
        XCTAssertTrue(pgn.hasSuffix("0-1") || pgn.contains("0-1\n"))
    }

    @MainActor
    func testSettingsRoundTrip() {
        let suite = "ChessTVTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        first.value.showCoordinates = false
        first.soundEnabled = false
        let second = SettingsStore(defaults: defaults)
        XCTAssertFalse(second.value.showCoordinates)
        XCTAssertFalse(second.soundEnabled)
        XCTAssertFalse(second.value.soundEffects)
    }
}
