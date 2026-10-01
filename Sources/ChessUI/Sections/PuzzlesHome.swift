import ChessContent
import ChessCore
import ChessPlay
import SwiftUI

/// The Puzzles tab: rated puzzles, Puzzle Rush, and the Daily Puzzle.
struct PuzzlesHome: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.locale)
  private var locale
  @State
  private var today = PuzzleDay(date: Date())

  var body: some View {
    let progress = model.puzzleProgress
    let best = PuzzleRushMode.allCases.map(progress.rushBest(for:)).max() ?? 0
    let streak = localization.plural("puzzles.streak", count: progress.progress.streak)
    let rating = localization.string("puzzles.rating.detail", progress.progress.rating)
    let rushBest = localization.string("puzzleRush.best", best)
    let date = PuzzleLayout.dateText(today, locale: locale)
    let dailyStatus = localization(
      progress.isDailySolved(today) ? "puzzleDaily.solved" : "puzzleDaily.notSolved"
    )
    WidthAdaptive {
      List {
        NavigationLink(value: AppRoute.ratedPuzzles) {
          PuzzleHomeRow(
            title: localization("puzzles.rated.title"),
            systemImage: "chart.line.uptrend.xyaxis",
            subtitle: streak,
            detail: rating
          )
        }
        NavigationLink(value: AppRoute.puzzleRush) {
          PuzzleHomeRow(
            title: localization("puzzleRush.title"),
            systemImage: "bolt",
            subtitle: rushBest
          )
        }
        NavigationLink(value: AppRoute.dailyPuzzle(today)) {
          PuzzleHomeRow(
            title: localization("puzzleDaily.title"),
            systemImage: "calendar",
            subtitle: date,
            detail: dailyStatus
          )
        }
      }
      .iconColumnLabels(model.catalog.interface)
    } wide: {
      CardGrid {
        NavigationLink(value: AppRoute.dailyPuzzle(today)) {
          CardLabel(
            title: localization("puzzleDaily.title"),
            subtitle: date,
            detail: dailyStatus,
            style: model.catalog.interface
          ) {
            if let daily = dailyPosition {
              BoardThumbnail(
                position: daily.position,
                flipped: daily.flipped,
                side: model.catalog.interface.home.thumbnailSize
                  * model.catalog.interface.platformScale
              )
            } else {
              SymbolBadge(systemImage: "calendar", style: model.catalog.interface)
            }
          }
        }
        .cardButtonStyle()
        NavigationLink(value: AppRoute.ratedPuzzles) {
          CardLabel(
            title: localization("puzzles.rated.title"),
            subtitle: streak,
            detail: rating,
            style: model.catalog.interface
          ) {
            SymbolBadge(systemImage: "chart.line.uptrend.xyaxis", style: model.catalog.interface)
          }
        }
        .cardButtonStyle()
        NavigationLink(value: AppRoute.puzzleRush) {
          CardLabel(
            title: localization("puzzleRush.title"),
            subtitle: localization("puzzleRush.detail"),
            detail: rushBest,
            style: model.catalog.interface
          ) {
            SymbolBadge(systemImage: "bolt", style: model.catalog.interface)
          }
        }
        .cardButtonStyle()
      }
    }
    .screenTitle(localization("section.puzzles.title"))
    .task { await followToday() }
  }

  /// Sets `today` now and again at each midnight while the tab stays on screen.
  private func followToday() async {
    today = PuzzleDay(date: Date())
    for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
      today = PuzzleDay(date: Date())
    }
  }

  /// Today's puzzle as the solver first sees it: after the opponent's move, from the
  /// solver's side.
  private var dailyPosition: (position: ChessPosition, flipped: Bool)? {
    let selector = PuzzleSelector(tuning: model.catalog.tuning.puzzleSelection)
    guard let puzzle = selector.daily(from: model.catalog.puzzles, day: today),
      let first = puzzle.moves.first,
      let position = try? puzzle.initialPosition().applying(first)
    else { return nil }
    return (position, position.sideToMove == .black)
  }
}

/// A Puzzles list row: symbol, title with a subtitle, and an optional detail.
private struct PuzzleHomeRow: View {
  let title: String
  let systemImage: String
  let subtitle: String
  var detail: String?

  var body: some View {
    HStack {
      Label {
        VStack(alignment: .leading) {
          Text(title)
          Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: systemImage)
      }
      Spacer(minLength: 0)
      if let detail { Text(detail).foregroundStyle(.secondary) }
    }
  }
}
