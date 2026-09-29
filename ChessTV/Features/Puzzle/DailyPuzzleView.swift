import SwiftUI
import ChessCore

/// Today's puzzle, picked deterministically by date. Unrated; playing it through to the end
/// (hints and retries allowed, not by revealing the solution) marks the day as solved.
struct DailyPuzzleView: View {
    @ObservedObject var progress: PuzzleProgressStore
    let day: PuzzleDay
    @StateObject private var model = PuzzleBoardModel()
    @FocusState private var panelFocus: PanelButton?

    private enum PanelButton: Hashable { case hint, solution, retry, again }

    var body: some View {
        PuzzleScreenLayout(board: PuzzleBoardArea(model: model, onExitRight: focusPanel, onBack: focusPanel)) {
            Text("Daily Puzzle").font(ChessFont.title)
            Text(dateText).font(ChessFont.body).foregroundStyle(ChessTheme.textSecondary)
            PuzzleStatusHeader(phase: model.phase, solverColor: model.solverColor)
            if let puzzle = model.session?.puzzle {
                PuzzleStatRow(label: "Puzzle rating", value: model.session?.isFinished == true ? "\(puzzle.rating)" : "?")
            }
            PuzzleStatRow(
                label: "Today",
                value: progress.isDailySolved(day) ? "Solved" : "Not solved",
                valueColor: progress.isDailySolved(day) ? ChessTheme.win : ChessTheme.textMuted
            )
            Spacer(minLength: 0)
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
                Button("Start Over", action: load)
                    .buttonStyle(.chessPrimary(icon: "arrow.uturn.backward", fullWidth: true))
                    .focused($panelFocus, equals: .again)
            }
        }
        .onAppear {
            if model.session == nil { load() }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .solved { progress.markDailySolved(day) }
        }
    }

    private var dateText: String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        guard let date = Calendar.current.date(from: components) else { return day.key }
        return date.formatted(date: .complete, time: .omitted)
    }

    private func focusPanel() {
        if model.canHint { panelFocus = .hint } else if model.canRetry { panelFocus = .retry } else { panelFocus = .again }
    }

    private func load() {
        guard let puzzle = PuzzleSelector.daily(from: PuzzleLibrary.all, day: day) else { return }
        model.load(puzzle)
    }
}
