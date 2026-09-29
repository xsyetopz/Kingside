import SwiftUI
import ChessCore

/// Entry point for puzzles: tiles for rated Puzzles, Puzzle Rush and the Daily Puzzle.
/// Owns the `PuzzleProgressStore` and passes it to the pushed screens.
struct PuzzlesHubView: View {
    @StateObject private var progress = PuzzleProgressStore()
    @EnvironmentObject private var settings: SettingsStore
    @State private var today = PuzzleDay(date: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 48) {
            Text("Puzzles").font(ChessFont.display)
            HStack(spacing: 40) {
                NavigationLink {
                    RatedPuzzlesView(progress: progress)
                } label: {
                    tile(icon: "puzzlepiece.extension.fill", title: "Puzzles", subtitle: "Rated") {
                        Text(verbatim: "\(progress.progress.rating)").font(ChessFont.display).monospacedDigit()
                        Text("Streak \(progress.progress.streak)").font(ChessFont.body)
                            .foregroundStyle(ChessTheme.textSecondary)
                    }
                }
                NavigationLink {
                    PuzzleRushView(progress: progress)
                } label: {
                    tile(icon: "bolt.fill", title: "Puzzle Rush", subtitle: "Beat the clock") {
                        Text("\(bestRushScore)").font(ChessFont.display).monospacedDigit()
                        Text("Best score").font(ChessFont.body).foregroundStyle(ChessTheme.textSecondary)
                    }
                }
                NavigationLink {
                    DailyPuzzleView(progress: progress, day: today)
                } label: {
                    tile(icon: "calendar", title: "Daily Puzzle", subtitle: today.key) {
                        if let daily = dailyPuzzle, let intro = daily.moves.first,
                           let position = try? daily.initialPosition?.applying(intro) {
                            ChessBoardDisplay.thumbnail(
                                position,
                                lastMove: intro,
                                isFlipped: position.sideToMove == .black,
                                theme: settings.value.boardTheme,
                                size: 150
                            )
                        }
                        Label(
                            progress.isDailySolved(today) ? "Solved" : "Not solved",
                            systemImage: progress.isDailySolved(today) ? "checkmark.circle.fill" : "circle"
                        )
                        .font(ChessFont.body)
                        .foregroundStyle(progress.isDailySolved(today) ? ChessTheme.win : ChessTheme.textSecondary)
                    }
                }
            }
            .buttonStyle(.panelCard)
            .focusSection()
            Spacer(minLength: 0)
        }
        .padding(80)
        .chessScreen()
        .onAppear { today = PuzzleDay(date: Date()) }
    }

    private var bestRushScore: Int {
        PuzzleRushMode.allCases.map(progress.rushBest(for:)).max() ?? 0
    }

    private var dailyPuzzle: Puzzle? { PuzzleSelector.daily(from: PuzzleLibrary.all, day: today) }

    private func tile<Content: View>(
        icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 44, weight: .bold)).foregroundStyle(ChessTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ChessFont.heading)
                    Text(subtitle).font(ChessFont.caption).foregroundStyle(ChessTheme.textMuted)
                }
            }
            Spacer(minLength: 0)
            content()
        }
        .frame(width: 460, height: 420, alignment: .topLeading)
    }
}
