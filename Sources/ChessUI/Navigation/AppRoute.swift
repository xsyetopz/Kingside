import ChessPlay

/// Top-level sections: tabs on iOS and tvOS, the sidebar on macOS.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
  case play, puzzles, games, account
  #if !os(macOS)
    /// On macOS, settings live in the Settings scene instead.
    case settings
  #endif

  var id: String { rawValue }
  var titleKey: String { "section.\(rawValue).title" }

  var systemImage: String {
    switch self {
    case .play: "checkerboard.rectangle"
    case .puzzles: "puzzlepiece"
    case .games: "clock.arrow.circlepath"
    case .account: "person.crop.circle"
    #if !os(macOS)
      case .settings: "gearshape"
    #endif
    }
  }
}

/// Screens pushed inside a section's navigation stack.
enum AppRoute: Hashable {
  case game(GameLaunch)
  case bots
  case passAndPlay
  case ratedPuzzles
  case puzzleRush
  case dailyPuzzle(PuzzleDay)
  case review(SavedGame.ID)
  case chessComLink
  case onlineLobby
  /// A game on Lichess, by its id.
  case onlineGame(id: String)
}
