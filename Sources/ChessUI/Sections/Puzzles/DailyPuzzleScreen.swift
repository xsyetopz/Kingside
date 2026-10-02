import ChessPlay
import SwiftUI

/// The Daily Puzzle of `day`. The session lives as long as the screen.
struct DailyPuzzleScreen: View {
  let day: PuzzleDay
  @Environment(AppModel.self)
  private var model
  @State
  private var session: DailyPuzzleSession?

  var body: some View {
    ZStack {
      if let session {
        DailyPuzzleView(session: session)
      }
    }
    .onAppear {
      guard session == nil else { return }
      let session = DailyPuzzleSession(
        day: day,
        catalog: model.catalog,
        progress: model.puzzleProgress,
        board: model.makePuzzleBoard()
      )
      session.start()
      self.session = session
    }
  }
}

/// The puzzle with the date and whether it is solved.
private struct DailyPuzzleView: View {
  let session: DailyPuzzleSession
  @Environment(\.localization)
  private var localization
  @Environment(\.locale)
  private var locale

  var body: some View {
    PuzzleScreenLayout(
      title: localization("puzzleDaily.title"),
      board: session.board,
      stats: [
        PuzzleStat(
          title: localization("puzzles.stat.date"),
          value: PuzzleLayout.dateText(session.day, locale: locale)
        ),
        PuzzleStat(
          title: localization("puzzles.stat.status"),
          value: localization(session.isSolved ? "puzzleDaily.solved" : "puzzleDaily.notSolved")
        ),
      ],
      primary: PuzzleAction(
        title: localization("puzzles.action.startOver"),
        systemImage: "arrow.counterclockwise"
      ) {
        session.startOver()
      }
    )
    .onChange(of: session.board.phase) { session.boardPhaseChanged() }
  }
}
