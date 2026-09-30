import ChessContent
import ChessCore
import ChessPlay
import Foundation
import Testing
@testable import ChessUI

struct GamesLayoutTests {
    private let localization = Localization()

    private func game(mode: GameMode, result: GameResult, plies: [String]) throws -> SavedGame {
        var chess = ChessGame()
        for uci in plies { _ = try chess.makeMove(#require(ChessMove(uci: uci))) }
        let clock = GameClock(timeControl: .untimed)
        let date = Date(timeIntervalSince1970: 1_768_478_400)
        let bot = PlayerInfo(name: "Maisie", rating: 400, botID: "maisie")
        let isBotGame = mode.botID != nil
        return SavedGame(
            createdAt: date, updatedAt: date, mode: mode,
            white: isBotGame ? PlayerInfo(name: "You") : PlayerInfo(name: "Ann"),
            black: isBotGame ? bot : PlayerInfo(name: "Bob"),
            timeControl: .untimed, autoFlip: false, game: chess, result: result,
            termination: result == .ongoing ? nil : .resignation, clock: clock)
    }

    @Test func botGameIsTitledByTheOpponent() throws {
        let saved = try game(mode: .bot(id: "maisie"), result: .whiteWon, plies: ["e2e4"])
        #expect(GamesLayout.title(saved, localization: localization) == "Maisie")
        #expect(GamesLayout.state(saved, localization: localization) == "You Won!")
    }

    @Test func passAndPlayIsTitledByBothPlayers() throws {
        let saved = try game(mode: .passAndPlay, result: .blackWon, plies: ["e2e4"])
        #expect(GamesLayout.title(saved, localization: localization) == "Ann vs Bob")
        #expect(GamesLayout.state(saved, localization: localization) == "Black Won")
    }

    @Test func unfinishedGameIsInProgress() throws {
        let saved = try game(mode: .passAndPlay, result: .ongoing, plies: [])
        #expect(GamesLayout.state(saved, localization: localization) == "In Progress")
    }

    @Test func moveCountRoundsUpToFullMoves() throws {
        #expect(GamesLayout.moveCount(try game(mode: .passAndPlay, result: .ongoing, plies: [])) == 0)
        #expect(GamesLayout.moveCount(try game(mode: .passAndPlay, result: .ongoing, plies: ["e2e4"])) == 1)
        #expect(GamesLayout.moveCount(try game(mode: .passAndPlay, result: .ongoing, plies: ["e2e4", "e7e5"])) == 1)
        #expect(GamesLayout.moveCount(try game(mode: .passAndPlay, result: .ongoing, plies: ["e2e4", "e7e5", "g1f3"])) == 2)
    }

    @Test func detailJoinsResultMovesAndDate() throws {
        let saved = try game(mode: .passAndPlay, result: .draw, plies: ["e2e4", "e7e5"])
        let detail = GamesLayout.detail(saved, localization: localization, locale: Locale(identifier: "en_US"))
        #expect(detail.hasPrefix("Draw · 1 move · "))
        #expect(detail.contains("2026"))
    }
}
