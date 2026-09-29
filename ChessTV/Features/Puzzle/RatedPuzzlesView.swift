import SwiftUI
import ChessCore

/// Rated puzzles: picks puzzles within ±200 of the player's rating without repeats,
/// updates the Elo rating on the first decisive result, and keeps a streak.
struct RatedPuzzlesView: View {
    @ObservedObject var progress: PuzzleProgressStore
    @StateObject private var model = PuzzleBoardModel()
    @State private var puzzle: Puzzle?
    @State private var ratingChange: Int?
    @State private var outcome: PuzzleSession.RatedOutcome?
    @FocusState private var panelFocus: PanelButton?

    private enum PanelButton: Hashable { case hint, solution, retry, next }

    var body: some View {
        PuzzleScreenLayout(board: PuzzleBoardArea(model: model, onExitRight: focusPanel, onBack: focusPanel)) {
            PuzzleStatusHeader(phase: model.phase, solverColor: model.solverColor)
            PuzzleStatRow(label: "Puzzle rating", value: puzzleRatingText)
            PuzzleStatRow(label: "Your rating", value: "\(progress.progress.rating)")
            if let ratingChange {
                PuzzleStatRow(label: "Change", value: ratingChange >= 0 ? "+\(ratingChange)" : "\(ratingChange)",
                              valueColor: ratingChange >= 0 ? ChessTheme.win : ChessTheme.lossBright)
            } else if outcome == .unrated {
                PuzzleStatRow(label: "Change", value: "Unrated", valueColor: ChessTheme.textMuted)
            }
            PuzzleStatRow(label: "Streak", value: "\(progress.progress.streak)", valueColor: ChessTheme.primary)
            Spacer(minLength: 0)
            buttons
        }
        .onAppear {
            model.onOutcome = record
            if puzzle == nil { next() }
        }
    }

    private var puzzleRatingText: String {
        guard let puzzle else { return "–" }
        return outcome == nil ? "?" : "\(puzzle.rating)"
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 20) {
            Button("Hint", action: model.hint)
                .buttonStyle(.chessSecondary(icon: "lightbulb.fill", fullWidth: true))
                .disabled(!model.canHint)
                .focused($panelFocus, equals: .hint)
            Button("Solution", action: model.showSolution)
                .buttonStyle(.chessSecondary(icon: "eye.fill", fullWidth: true))
                .disabled(!model.canShowSolution)
                .focused($panelFocus, equals: .solution)
        }
        HStack(spacing: 20) {
            Button("Retry", action: model.retry)
                .buttonStyle(.chessSecondary(icon: "arrow.counterclockwise", fullWidth: true))
                .disabled(!model.canRetry)
                .focused($panelFocus, equals: .retry)
            Button("Next", action: next)
                .buttonStyle(.chessPrimary(icon: "arrow.right", fullWidth: true))
                .disabled(outcome == nil)
                .focused($panelFocus, equals: .next)
        }
    }

    private func focusPanel() {
        if outcome != nil { panelFocus = .next } else if model.canHint { panelFocus = .hint } else { panelFocus = .solution }
    }

    private func record(_ result: PuzzleSession.RatedOutcome) {
        outcome = result
        guard let puzzle else { return }
        switch result {
        case .solved, .failed:
            ratingChange = progress.recordRated(puzzleRating: puzzle.rating, solved: result == .solved)
        case .unrated:
            progress.recordStreak(solved: false)
        }
    }

    private func next() {
        var generator = SystemRandomNumberGenerator()
        var pick = PuzzleSelector.rated(
            from: PuzzleLibrary.all, rating: progress.progress.rating, seen: progress.progress.seenIDs, using: &generator
        )
        if pick == nil {
            progress.resetSeen()
            pick = PuzzleSelector.rated(from: PuzzleLibrary.all, rating: progress.progress.rating, seen: [], using: &generator)
        }
        guard let pick else { return }
        progress.markSeen(pick.id)
        puzzle = pick
        outcome = nil
        ratingChange = nil
        model.load(pick)
    }
}
