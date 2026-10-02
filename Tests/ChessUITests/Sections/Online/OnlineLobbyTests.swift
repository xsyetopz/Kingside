import ChessContent
import ChessPlay
import Foundation
import LichessLink
import Testing
@testable import ChessUI

struct OnlineLobbyTests {
  private let localization = Localization()

  private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  @Test
  func seekPresetsAreRapidAndClassicalOnly() {
    #expect(OnlineLobby.seekPresets.map(\.id) == ["10+0", "10+5", "15+10", "30+0", "30+20"])
    #expect(OnlineLobby.categories(of: OnlineLobby.seekPresets) == [.rapid, .classical])
  }

  @Test
  func challengePresetsStartWithBlitz() {
    #expect(OnlineLobby.challengePresets.map(\.id) == ["3+2", "5+3", "10+0", "15+10", "30+0"])
    #expect(
      OnlineLobby.categories(of: OnlineLobby.challengePresets) == [.blitz, .rapid, .classical]
    )
    #expect(
      OnlineLobby.presets(OnlineLobby.challengePresets, in: .rapid).map(\.id) == ["10+0", "15+10"]
    )
  }

  @Test
  func presetsSendSecondsToChallengesAndMinutesToSeeks() throws {
    let preset = try #require(OnlineLobby.seekPresets.last)
    #expect(preset.minutes == 30)
    #expect(preset.increment == 20)
    #expect(preset.limitSeconds == 1800)
  }

  @Test
  func timeControlLabels() throws {
    #expect(
      OnlineLobby.label(limitSeconds: 600, increment: 0, localization: localization) == "10 min"
    )
    #expect(
      OnlineLobby.label(limitSeconds: 900, increment: 10, localization: localization) == "15 | 10"
    )
    #expect(
      OnlineLobby.label(limitSeconds: 45, increment: 0, localization: localization) == "45 sec"
    )
    #expect(
      OnlineLobby.label(limitSeconds: 90, increment: 1, localization: localization) == "90 sec | 1"
    )
    let clock = try decode(#"{"type":"clock","limit":180,"increment":2}"#) as LichessTimeControl
    #expect(OnlineLobby.label(clock, localization: localization) == "3 | 2")
    let daily = try decode(#"{"type":"correspondence","daysPerTurn":3}"#) as LichessTimeControl
    #expect(OnlineLobby.label(daily, localization: localization) == "3 days per move")
    #expect(
      OnlineLobby.label(
        try decode(#"{"type":"unlimited"}"#) as LichessTimeControl,
        localization: localization
      ) == "No timer"
    )
  }

  @Test
  func challengerNameShowsTheRatingWhenKnown() throws {
    let rated =
      try decode(#"{"id":"philippe","name":"Philippe","rating":1790}"#) as LichessChallengeUser
    let unrated = try decode(#"{"id":"anon","name":"Anon"}"#) as LichessChallengeUser
    #expect(OnlineLobby.name(rated, localization: localization) == "Philippe (1790)")
    #expect(OnlineLobby.name(unrated, localization: localization) == "Anon")
  }

  @Test
  func usernamesFollowLichessRules() {
    #expect(OnlineLobby.isValidUsername("Philippe_2-b"))
    #expect(!OnlineLobby.isValidUsername("a"))
    #expect(!OnlineLobby.isValidUsername("has space"))
    #expect(!OnlineLobby.isValidUsername(String(repeating: "a", count: 31)))
  }

  @Test
  func colorChoicesMapToLichessColors() {
    #expect(BotColorChoice.white.lichessColor == .white)
    #expect(BotColorChoice.black.lichessColor == .black)
    #expect(BotColorChoice.random.lichessColor == .random)
  }

  @Test
  func everyLobbyKeyIsLocalized() {
    let keys =
      OnlineLobby.Category.allCases.map(\.nameKey)
      + [
        "online.lobby.title", "online.error.notAllowed", "online.connection.error",
        "play.online.title", "play.online.detail",
      ]
      + [
        OnlineLobby.colorKey(.white), OnlineLobby.colorKey(.black), "game.turn.yours",
        "game.turn.opponent",
      ]
    for key in keys { #expect(localization(key) != key, "\(key)") }
  }
}
