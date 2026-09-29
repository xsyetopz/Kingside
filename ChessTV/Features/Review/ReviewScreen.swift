import SwiftUI
import ChessCore

/// Route destination for `.review(id)`: loads the saved game, runs the analysis while the screen
/// is shown, and switches between the summary and the move-by-move review.
struct ReviewScreen: View {
    let gameID: UUID
    @EnvironmentObject private var container: AppContainer
    @State private var model: GameReviewModel?
    @State private var missing = false
    @State private var showingMoves = false

    var body: some View {
        Group {
            if let model {
                if showingMoves {
                    ReviewStepView(model: model) { showingMoves = false }
                } else {
                    ReviewSummaryView(model: model) { showingMoves = true }
                }
            } else if missing {
                Text("This game is no longer saved.")
                    .font(ChessFont.heading)
                    .foregroundStyle(ChessTheme.textSecondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chessScreen()
        .task {
            if model == nil {
                if let game = await container.gameStore.allGames().first(where: { $0.id == gameID }) {
                    model = GameReviewModel(game: game, engine: container.engine)
                } else {
                    missing = true
                }
            }
            model?.start()
        }
        .onDisappear { model?.stop() }
    }
}

/// First review page: both players' accuracy, classification counts and the evaluation graph.
struct ReviewSummaryView: View {
    @ObservedObject var model: GameReviewModel
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(alignment: .leading, spacing: 36) {
                Text("Game Review")
                    .font(ChessFont.title)
                    .foregroundStyle(ChessTheme.textPrimary)
                HStack(spacing: 40) {
                    player(.white)
                    player(.black)
                }
                EvaluationGraph(
                    probabilities: model.analyses.map { WinProbability.white($0.evaluation) },
                    plyCount: model.moveCount,
                    markers: model.moves.filter { $0.classification.isError }.map { ($0.ply + 1, $0.classification) }
                )
                .frame(height: 200)
                progress
                Button("Start Review", action: onStart)
                    .buttonStyle(.chessPrimary(icon: "play.fill", fullWidth: true))
                    .disabled(model.moves.isEmpty)
            }
            .frame(width: 900)
            classificationTable
        }
    }

    private func player(_ color: PieceColor) -> some View {
        let info = model.game.player(color)
        return VStack(spacing: 14) {
            ReviewPlayerAvatar(player: info, size: 120)
            Text(info.name)
                .font(ChessFont.body)
                .foregroundStyle(ChessTheme.textPrimary)
                .lineLimit(1)
            Text(model.accuracy(for: color).map { String(format: "%.1f", $0) } ?? "–")
                .font(ChessFont.display)
                .foregroundStyle(color == .white ? Color(hex: 0x262522) : .white)
                .frame(width: 300, height: 110)
                .background(color == .white ? Color.white : Color(hex: 0x1A1917), in: RoundedRectangle(cornerRadius: 14))
            Text("Accuracy")
                .font(ChessFont.caption)
                .foregroundStyle(ChessTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var progress: some View {
        if !model.isComplete {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: Double(model.moves.count), total: Double(max(model.moveCount, 1)))
                    .tint(ChessTheme.primary)
                HStack {
                    Text(model.isAnalyzing ? "Analyzing… \(model.moves.count)/\(model.moveCount)"
                                           : "Paused at \(model.moves.count)/\(model.moveCount)")
                        .font(ChessFont.body)
                        .foregroundStyle(ChessTheme.textSecondary)
                    Spacer()
                    if model.isAnalyzing {
                        Button("Stop") { model.stop() }.buttonStyle(.chessSecondary(icon: "stop.fill"))
                    } else {
                        Button("Resume") { model.start() }.buttonStyle(.chessSecondary(icon: "play.fill"))
                    }
                }
            }
        }
    }

    private var classificationTable: some View {
        VStack(spacing: 10) {
            HStack {
                Text(model.game.white.name).frame(width: 190, alignment: .center)
                Spacer()
                Text(model.game.black.name).frame(width: 190, alignment: .center)
            }
            .font(ChessFont.caption)
            .foregroundStyle(ChessTheme.textSecondary)
            .lineLimit(1)
            ForEach(MoveClassification.allCases, id: \.self) { classification in
                HStack {
                    count(classification, .white)
                    Spacer()
                    HStack(spacing: 14) {
                        ClassificationIcon(classification: classification, diameter: 40)
                        Text(classification.title)
                            .font(ChessFont.body)
                            .foregroundStyle(ChessTheme.textPrimary)
                    }
                    .frame(width: 260, alignment: .leading)
                    Spacer()
                    count(classification, .black)
                }
                .frame(height: 58)
            }
        }
        .frame(maxWidth: .infinity)
        .chessPanel()
    }

    private func count(_ classification: MoveClassification, _ color: PieceColor) -> some View {
        Text("\(model.count(classification, for: color))")
            .font(ChessFont.rounded(36, weight: .heavy))
            .foregroundStyle(classification.color)
            .frame(width: 190)
    }
}
