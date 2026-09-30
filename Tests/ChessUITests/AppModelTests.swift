import ChessContent
import ChessPlay
import Foundation
import Testing
@testable import ChessUI

@MainActor
struct AppModelTests {
    private let suiteName = "ChessUITests.\(UUID().uuidString)"
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ChessUITests-\(UUID().uuidString)")

    private func makeModel() throws -> AppModel {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let storage = AppModel.Storage(
            defaults: defaults, gamesFileURL: directory.appending(path: GamePersistenceStore.fileName), playsFeedback: false)
        return AppModel(catalog: try ContentCatalog.load(), storage: storage)
    }

    @Test func uiTestingArgumentUsesThrowawayStorageAndNoFeedback() {
        let storage = AppModel.Storage.live(arguments: ["Kingside", "--uitesting"])
        #expect(storage.defaults != .standard)
        #expect(storage.gamesFileURL.path().hasPrefix(FileManager.default.temporaryDirectory.path()))
        #expect(!storage.playsFeedback)
    }

    @Test func appearanceFollowsSettingsAndFallsBackToDefaults() throws {
        let model = try makeModel()
        #expect(model.boardTheme.id == model.catalog.defaults.boardThemeID)
        #expect(model.pieceSet.id == model.catalog.defaults.pieceSetID)

        let other = try #require(model.catalog.boardThemes.first { $0.id != model.catalog.defaults.boardThemeID })
        model.settings.value.boardTheme = other.id
        #expect(model.boardTheme == other)

        model.settings.value.boardTheme = "no-such-theme"
        #expect(model.boardTheme.id == model.catalog.defaults.boardThemeID)
    }

    @Test func freshStoreHasNoGameToContinue() async throws {
        let model = try makeModel()
        await model.reloadGames()
        #expect(model.savedGames.isEmpty)
        #expect(model.unfinishedGame == nil)
    }

    @Test func unreadableGamesFileIsReportedNotShownAsEmpty() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: GamePersistenceStore.fileName)
        try Data("not json".utf8).write(to: fileURL)
        let model = try makeModel()
        await model.reloadGames()
        #expect(model.savedGamesUnreadable)
        #expect(model.savedGames.isEmpty)
    }

    @Test func userAgentNamesTheContact() throws {
        let catalog = try ContentCatalog.load()
        let agent = catalog.services.userAgent(product: "Kingside", version: "1.0")
        #expect(agent.contains(catalog.services.contact))
    }
}
