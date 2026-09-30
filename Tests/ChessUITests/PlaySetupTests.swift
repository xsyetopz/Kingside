import ChessContent
import ChessCore
import ChessPlay
import Testing
@testable import ChessUI

struct PlaySetupTests {
    private let localization = Localization()

    @Test func fixedColorChoicesIgnoreTheDice() {
        #expect(PlaySetup.humanColor(for: .white, random: { false }) == .white)
        #expect(PlaySetup.humanColor(for: .black, random: { true }) == .black)
    }

    @Test func randomChoiceFollowsTheDice() {
        #expect(PlaySetup.humanColor(for: .random, random: { true }) == .white)
        #expect(PlaySetup.humanColor(for: .random, random: { false }) == .black)
    }

    @Test func botGamePutsTheBotOnTheOtherSide() throws {
        let catalog = try ContentCatalog.load()
        let bot = try #require(catalog.bots.bots.first)
        let setup = PlaySetup.versus(bot, choice: .black, localization: localization)
        #expect(setup.mode == .bot(id: bot.id))
        #expect(setup.white.botID == bot.id)
        #expect(setup.black.botID == nil)
        #expect(setup.timeControl == .untimed)
    }

    @Test func passAndPlayUsesThePresetAndTheFlipOption() throws {
        let catalog = try ContentCatalog.load()
        let preset = try #require(catalog.timeControls.presets.first { $0.isTimed })
        let setup = PlaySetup.passAndPlay(preset: preset, autoFlip: true, localization: localization)
        #expect(setup.mode == .passAndPlay)
        #expect(setup.timeControl == TimeControl(preset))
        #expect(setup.autoFlip)
        #expect(!setup.white.isBot && !setup.black.isBot)
        #expect(setup.white.name != setup.black.name)
    }

    @Test func everyPresetAppearsOnceInCatalogOrder() throws {
        let catalog = try ContentCatalog.load().timeControls
        let groups = PlaySetup.presetsByCategory(catalog)
        #expect(groups.flatMap(\.presets).map(\.id).sorted() == catalog.presets.map(\.id).sorted())
        #expect(groups.map(\.category.id) == catalog.categories.map(\.id).filter { id in groups.contains { $0.category.id == id } })
    }
}
