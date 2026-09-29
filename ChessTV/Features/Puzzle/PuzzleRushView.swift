import SwiftUI
import ChessCore

/// Puzzle Rush: pick a mode, solve escalating puzzles against the clock (or until three
/// strikes in Survival), then see the score and best score.
struct PuzzleRushView: View {
    @ObservedObject var progress: PuzzleProgressStore
    @State private var mode: PuzzleRushMode?
    @State private var result: RushResult?
    @State private var runID = UUID()

    struct RushResult: Equatable {
        let mode: PuzzleRushMode
        let score: Int
        let isNewBest: Bool
    }

    var body: some View {
        Group {
            if let result {
                PuzzleRushEndView(result: result, best: progress.rushBest(for: result.mode)) {
                    self.result = nil
                    runID = UUID()
                    mode = result.mode
                } onChangeMode: {
                    self.result = nil
                    mode = nil
                }
            } else if let mode {
                PuzzleRushRunView(mode: mode) { score in
                    let isNewBest = progress.recordRush(mode: mode, score: score)
                    result = RushResult(mode: mode, score: score, isNewBest: isNewBest)
                }
                .id(runID)
            } else {
                modePicker
            }
        }
        .chessScreen()
    }

    private var modePicker: some View {
        VStack(spacing: 48) {
            Text("Puzzle Rush").font(ChessFont.display)
            Text("Solve as many puzzles as you can. Three mistakes and you're out.")
                .font(ChessFont.body).foregroundStyle(ChessTheme.textSecondary)
            HStack(spacing: 40) {
                ForEach(PuzzleRushMode.allCases) { option in
                    Button {
                        runID = UUID()
                        mode = option
                    } label: {
                        VStack(spacing: 20) {
                            Image(systemName: option.icon).font(.system(size: 72, weight: .bold))
                                .foregroundStyle(ChessTheme.primary)
                                .frame(height: 96)
                            Text(option.title).font(ChessFont.heading)
                            Text("Best: \(progress.rushBest(for: option))")
                                .font(ChessFont.body).foregroundStyle(ChessTheme.textSecondary)
                        }
                        .frame(width: 380, height: 300)
                    }
                    .buttonStyle(.panelCard)
                }
            }
            .focusSection()
        }
    }
}

/// One running rush: board, score, strikes and clock.
private struct PuzzleRushRunView: View {
    let mode: PuzzleRushMode
    let onFinish: (Int) -> Void
    @StateObject private var model = PuzzleBoardModel()
    @State private var run: PuzzleRushRun
    @State private var used: Set<String> = []
    @State private var finished = false
    @FocusState private var endFocused: Bool

    static let nextPuzzleDelay: Duration = .milliseconds(700)

    init(mode: PuzzleRushMode, onFinish: @escaping (Int) -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        _run = State(initialValue: PuzzleRushRun(mode: mode))
    }

    var body: some View {
        PuzzleScreenLayout(board: PuzzleBoardArea(model: model, onExitRight: focusPanel, onBack: focusPanel)) {
            HStack {
                Text(mode.title).font(ChessFont.heading)
                Spacer()
                ClockView(
                    time: run.remaining ?? .infinity,
                    isActive: run.remaining != nil && !finished,
                    isLow: (run.remaining ?? .infinity) < 30
                )
            }
            PuzzleStatusHeader(phase: model.phase, solverColor: model.solverColor)
            HStack(alignment: .firstTextBaseline) {
                Text("Score").font(ChessFont.heading).foregroundStyle(ChessTheme.textSecondary)
                Spacer()
                Text("\(run.score)").font(ChessFont.display).foregroundStyle(ChessTheme.primary).monospacedDigit()
            }
            HStack(spacing: 20) {
                ForEach(0..<PuzzleRushRun.maxStrikes, id: \.self) { index in
                    Image(systemName: "xmark")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(index < run.strikes ? ChessTheme.lossBright : ChessTheme.raised)
                        .frame(width: 72, height: 72)
                        .background(ChessTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Spacer(minLength: 0)
            Button("End Run", action: finish)
                .buttonStyle(.chessSecondary(icon: "flag.fill", fullWidth: true))
                .focused($endFocused)
        }
        .onAppear {
            model.onOutcome = record
            if model.session == nil { loadNext() }
        }
        .task(id: mode) { await runClock() }
    }

    private func focusPanel() { endFocused = true }

    private func runClock() async {
        guard mode.timeLimit != nil else { return }
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled && !finished {
            try? await Task.sleep(for: .milliseconds(100))
            let now = clock.now
            let elapsed = now - last
            last = now
            // Hold the clock during the opponent's first move of each puzzle.
            guard model.phase != .intro else { continue }
            run.tick(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            if run.isOver { finish() }
        }
    }

    private func record(_ outcome: PuzzleSession.RatedOutcome) {
        guard !finished else { return }
        if outcome == .solved { run.recordSolved() } else { run.recordFailed() }
        if run.isOver {
            Task {
                try? await Task.sleep(for: Self.nextPuzzleDelay)
                finish()
            }
            return
        }
        Task {
            try? await Task.sleep(for: Self.nextPuzzleDelay)
            guard !finished else { return }
            loadNext()
        }
    }

    private func loadNext() {
        var generator = SystemRandomNumberGenerator()
        guard let puzzle = PuzzleSelector.rush(
            from: PuzzleLibrary.all, index: run.puzzlesPlayed, excluding: used, using: &generator
        ) else {
            finish()
            return
        }
        used.insert(puzzle.id)
        model.load(puzzle)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish(run.score)
    }
}

private struct PuzzleRushEndView: View {
    let result: PuzzleRushView.RushResult
    let best: Int
    let onPlayAgain: () -> Void
    let onChangeMode: () -> Void

    var body: some View {
        VStack(spacing: 36) {
            Text("Puzzle Rush · \(result.mode.title)").font(ChessFont.heading).foregroundStyle(ChessTheme.textSecondary)
            Text("\(result.score)").font(.system(size: 180, weight: .heavy, design: .rounded)).foregroundStyle(ChessTheme.primary)
            Text(result.isNewBest ? "New personal best!" : "Best: \(best)")
                .font(ChessFont.title)
                .foregroundStyle(result.isNewBest ? ChessTheme.primary : ChessTheme.textPrimary)
            HStack(spacing: 32) {
                Button("Play Again", action: onPlayAgain).buttonStyle(.chessPrimary(icon: "arrow.clockwise"))
                Button("Change Mode", action: onChangeMode).buttonStyle(.chessSecondary(icon: "list.bullet"))
            }
            .focusSection()
        }
        .padding(80)
        .chessPanel(padding: 60)
    }
}
