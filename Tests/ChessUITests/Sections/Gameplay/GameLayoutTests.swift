import ChessContent
import Foundation
import Testing
@testable import ChessUI

struct GameLayoutTests {
  private var style: GameLayoutStyle {
    get throws {
      let json =
        #"{"wideAspectRatio": 1.3, "panelWidth": 340, "avatarSize": 44, "compactHeight": 480}"#
      return try JSONDecoder().decode(GameLayoutStyle.self, from: Data(json.utf8))
    }
  }

  @Test
  func wideScreensPutThePanelBesideTheBoard() throws {
    let style = try style
    #expect(GameLayout.isWide(CGSize(width: 1024, height: 768), style: style))
    #expect(GameLayout.isWide(CGSize(width: 1300, height: 1000), style: style))
    #expect(!GameLayout.isWide(CGSize(width: 390, height: 700), style: style))
    #expect(!GameLayout.isWide(CGSize(width: 800, height: 800), style: style))
    #expect(!GameLayout.isWide(.zero, style: style))
  }

  @Test
  func shortScreensMoveThePlayerBarsIntoThePanel() throws {
    let style = try style
    #expect(GameLayout.barsInPanel(CGSize(width: 750, height: 300), style: style))
    #expect(!GameLayout.barsInPanel(CGSize(width: 1300, height: 950), style: style))
    #expect(!GameLayout.barsInPanel(CGSize(width: 800, height: 480), style: style))
  }

  @Test
  func clockTextShowsMinutesAndRoundsPartialSecondsUp() {
    #expect(GameLayout.clockText(180) == "3:00")
    #expect(GameLayout.clockText(59.2) == "1:00")
    #expect(GameLayout.clockText(9) == "0:09")
    #expect(GameLayout.clockText(0) == "0:00")
    #expect(GameLayout.clockText(-3) == "0:00")
    #expect(GameLayout.clockText(3600) == "1:00:00")
    #expect(GameLayout.clockText(5025) == "1:23:45")
  }
}
