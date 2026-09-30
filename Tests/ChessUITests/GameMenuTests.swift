#if !os(tvOS)
import ChessContent
import ChessCore
import ChessPlay
import Foundation
import Testing
@testable import ChessUI

@MainActor
struct GameMenuTests {
    private let suiteName = "ChessUITests.\(UUID().uuidString)"
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ChessUITests-\(UUID().uuidString)")

    private func makeSession() throws -> GameSession {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let storage = AppModel.Storage(
            defaults: defaults, gamesFileURL: directory.appending(path: GamePersistenceStore.fileName), playsFeedback: false)
        let model = AppModel(catalog: try ContentCatalog.load(), storage: storage)
        return model.makeGameSession(.new(GameSetup(
            mode: .passAndPlay, white: PlayerInfo(name: "A"), black: PlayerInfo(name: "B"), timeControl: .untimed)))
    }

    private func play(_ uci: String, in session: GameSession) throws {
        let move = try #require(ChessMove(uci: uci))
        session.apply(.select(move.from))
        session.apply(.select(move.to))
    }

    @Test func puzzleTargetOnlyFlipsTheBoard() {
        let target = GameMenuTarget(flip: {})
        #expect(!target.canHint)
        #expect(!target.canTakeback)
        #expect(!target.canOfferDraw)
        #expect(!target.canResign)
        #expect(!target.canStartAgain)
    }

    @Test func itemsFollowTheGameState() throws {
        let session = try makeSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = GameMenuTarget(session: session, flip: {})

        #expect(target.canHint && target.canOfferDraw && target.canResign)
        #expect(!target.canTakeback)
        #expect(!target.canStartAgain)

        try play("e2e4", in: session)
        #expect(target.canTakeback)

        session.apply(.offerDraw)
        #expect(!target.canOfferDraw)
        #expect(!target.canHint)
        session.apply(.declineDraw)
        #expect(target.canOfferDraw && target.canHint)

        session.apply(.resign)
        #expect(session.isGameOver)
        #expect(!target.canHint && !target.canTakeback && !target.canOfferDraw && !target.canResign)
        #expect(target.canStartAgain)
    }
}
#endif
