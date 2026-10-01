import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@Suite
struct LocalizationKeyTests {
  /// Every localisation key ChessPlay builds or looks up.
  private static var usedKeys: [String] {
    MoveClassification.allCases.flatMap { [$0.titleKey, $0.coachKey] }
      + ["review.coach.bestMove"]
      + PuzzleRushMode.allCases.map(\.nameKey)
      + BoardOrientation.allCases.map(\.titleKey)
      + BotColorChoice.allCases.map(\.titleKey)
      + GameTermination.allCases.map(\.reasonKey)
      + ["player.you.name"]
      + gameSessionKeys
  }

  private static var gameSessionKeys: [String] {
    let humans: [PieceColor?] = [.white, .black, nil]
    let results: [GameResult] = [.whiteWon, .blackWon, .draw]
    let titles = results.flatMap { result in
      humans.compactMap { GameSession.resultTitleKey(result, humanColor: $0) }
    }
    let turns = humans.flatMap { human in
      [PieceColor.white, .black].map {
        GamePresentation.turnTextKey(sideToMove: $0, humanColor: human)
      }
    }
    return titles + turns + ["game.turn.check", "game.status.botThinking", "game.status.over"]
  }

  @Test
  func everyUsedKeyExistsInSourceEnglish() {
    // A sentinel default comes back only when no packaged value exists.
    let missing = Self.usedKeys.filter {
      Shared.english.string($0, defaultValue: "\u{0}") == "\u{0}"
    }
    #expect(missing.isEmpty, "en-US has no keys: \(missing.joined(separator: ", "))")
  }
}
