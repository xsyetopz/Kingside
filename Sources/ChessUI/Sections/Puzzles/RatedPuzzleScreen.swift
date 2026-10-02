import ChessPlay
import SwiftUI

/// Rated puzzles near the player's rating. The session lives as long as the screen.
struct RatedPuzzleScreen: View {
  @Environment(AppModel.self)
  private var model
  @State
  private var session: RatedPuzzleSession?

  var body: some View {
    ZStack {
      if let session {
        RatedPuzzleView(session: session)
      }
    }
    .onAppear {
      guard session == nil else { return }
      let session = RatedPuzzleSession(
        catalog: model.catalog,
        progress: model.puzzleProgress,
        board: model.makePuzzleBoard()
      )
      session.start()
      self.session = session
    }
  }
}

/// The puzzle with the rating, streak, and the change of the last attempt.
private struct RatedPuzzleView: View {
  let session: RatedPuzzleSession
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let progress = model.puzzleProgress.progress
    var stats = [
      PuzzleStat(title: localization("puzzles.stat.rating"), value: String(progress.rating)),
      PuzzleStat(title: localization("puzzles.stat.streak"), value: String(progress.streak)),
    ]
    if let change = session.ratingChange {
      stats.append(
        PuzzleStat(
          title: localization("puzzles.stat.change"),
          value: PuzzleLayout.ratingChangeText(change)
        )
      )
    }
    return PuzzleScreenLayout(
      title: localization("puzzles.rated.title"),
      board: session.board,
      stats: stats,
      primary: PuzzleAction(
        title: localization("puzzles.action.next"),
        systemImage: "forward.fill",
        isEnabled: session.outcome != nil
      ) { session.next() }
    )
  }
}
