import SwiftUI
import ChessCore

/// Move-by-move review: board with the classification badge and best-move arrow, evaluation
/// bar, coach line, move list and step controls. Left/right on the focused board steps through
/// the moves; down moves focus to the buttons; Menu returns to the summary.
struct ReviewStepView: View {
    @ObservedObject var model: GameReviewModel
    let onClose: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    /// Number of moves played on the shown board (0 = start position).
    @State private var current = 0
    @State private var preview: (position: ChessPosition, move: ChessMove?)?
    @State private var previewTask: Task<Void, Never>?
    @FocusState private var focus: StepFocus?

    private enum StepFocus: Hashable { case board, controls }

    private static let boardSize: CGFloat = 820

    private var isFlipped: Bool { model.game.humanColor == .black }
    /// Review of the move that led to the shown position, once analysed.
    private var reviewed: ReviewedMove? {
        current > 0 && current - 1 < model.moves.count ? model.moves[current - 1] : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            EvaluationBar(
                evaluation: current < model.analyses.count ? model.analyses[current].evaluation : nil,
                isFlipped: isFlipped
            )
            .frame(width: 40, height: Self.boardSize)
            VStack(spacing: 28) {
                board
                controls
            }
            panel
        }
        .onAppear { focus = .board }
        .defaultFocus($focus, .board)
        .onExitCommand { stopPreview(); onClose() }
        .onDisappear { stopPreview() }
    }

    private var board: some View {
        let shownMove = current > 0 ? model.game.game.moves[current - 1].move : nil
        var arrows: [BoardArrow] = []
        var badges: [BoardBadge] = []
        if preview == nil, let reviewed, let shownMove {
            badges = [reviewed.classification.badge(on: shownMove.to)]
            if reviewed.classification.showsBestMove, let best = reviewed.bestMove {
                arrows = [BoardArrow(from: best.from, to: best.to, color: BoardArrow.best)]
            }
        }
        return ChessBoardDisplay(
            position: preview?.position ?? model.positions[current],
            lastMove: preview == nil ? shownMove : preview?.move,
            isFlipped: isFlipped,
            theme: settings.value.boardTheme,
            arrows: arrows,
            badges: badges
        )
        .frame(width: Self.boardSize, height: Self.boardSize)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white, lineWidth: focus == .board ? 5 : 0)
        )
        .focusable()
        .focused($focus, equals: .board)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            case .down: focus = .controls
            default: break
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button("Previous") { step(-1) }
                .buttonStyle(.chessSecondary(icon: "chevron.left"))
                .disabled(current == 0)
            Button(preview == nil ? "Best line" : "Hide line") { toggleBestLine() }
                .buttonStyle(.chessSecondary(icon: "lightbulb.fill"))
                .disabled(reviewed?.bestLine.isEmpty ?? true)
            Button("Next") { step(1) }
                .buttonStyle(.chessPrimary(icon: "chevron.right"))
                .disabled(current == model.moveCount)
                .focused($focus, equals: .controls)
        }
        .onMoveCommand { direction in
            if direction == .up { focus = .board }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 24) {
            coach
            EvaluationGraph(
                probabilities: model.analyses.map { WinProbability.white($0.evaluation) },
                plyCount: model.moveCount,
                markers: model.moves.filter { $0.classification.isError }.map { ($0.ply + 1, $0.classification) },
                highlightedPly: current
            )
            .frame(height: 110)
            moveList
        }
        .frame(maxWidth: .infinity, maxHeight: Self.boardSize + 108, alignment: .top)
        .chessPanel()
    }

    private var coach: some View {
        HStack(alignment: .top, spacing: 20) {
            if let reviewed {
                ClassificationIcon(classification: reviewed.classification, diameter: 60)
            } else {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(ChessTheme.textSecondary)
                    .frame(width: 60, height: 60)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(coachText)
                    .font(ChessFont.subheading)
                    .foregroundStyle(ChessTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reviewed {
                    Text("Evaluation \(EvaluationLabel.text(reviewed.evaluationAfter))")
                        .font(ChessFont.caption)
                        .foregroundStyle(ChessTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
    }

    private var coachText: String {
        if preview != nil { return "Engine line: \(bestLineSAN)" }
        if current == 0 { return "Step through the game with left and right." }
        return reviewed?.coachText ?? "Analyzing \(model.game.game.moves[current - 1].san)…"
    }

    private var moveList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<(model.moveCount + 1) / 2, id: \.self) { row in
                        HStack(spacing: 12) {
                            Text("\(row + 1).")
                                .font(ChessFont.caption)
                                .foregroundStyle(ChessTheme.textMuted)
                                .frame(width: 70, alignment: .leading)
                            moveCell(row * 2)
                            moveCell(row * 2 + 1)
                        }
                        .id(row)
                    }
                }
            }
            .onChange(of: current) { _, value in
                withAnimation { proxy.scrollTo(max(value - 1, 0) / 2, anchor: .center) }
            }
        }
    }

    @ViewBuilder private func moveCell(_ ply: Int) -> some View {
        if ply < model.moveCount {
            HStack(spacing: 10) {
                if ply < model.moves.count {
                    ClassificationIcon(classification: model.moves[ply].classification, diameter: 28)
                }
                Text(model.game.game.moves[ply].san)
                    .font(ChessFont.body)
                    .foregroundStyle(ChessTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(width: 260, alignment: .leading)
            .background(ply == current - 1 ? ChessTheme.focusSurface : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var bestLineSAN: String {
        guard current > 0, let line = reviewed?.bestLine else { return "" }
        var position = model.positions[current - 1]
        var sans: [String] = []
        for move in line {
            guard let san = try? ChessNotation.san(for: move, in: position), (try? position.apply(move)) != nil else { break }
            sans.append(san)
        }
        return sans.joined(separator: " ")
    }

    private func step(_ delta: Int) {
        stopPreview()
        current = min(max(current + delta, 0), model.moveCount)
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        preview = nil
    }

    /// Plays the engine's best line from the position before the shown move, one move per second.
    private func toggleBestLine() {
        guard preview == nil, current > 0, let line = reviewed?.bestLine, !line.isEmpty else {
            stopPreview()
            return
        }
        let start = model.positions[current - 1]
        previewTask = Task { @MainActor in
            var position = start
            for move in line {
                guard let next = try? position.applying(move) else { break }
                position = next
                preview = (next, move)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
        }
    }
}
