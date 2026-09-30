import ChessContent
import ChessPlay
import SwiftUI

/// The review of a saved game: the board at a ply, the analysis as it arrives, and the moves.
/// The analysis stops when the screen goes away.
struct ReviewScreen: View {
    let gameID: SavedGame.ID
    @Environment(AppModel.self) private var model
    @State private var review: GameReviewModel?

    var body: some View {
        ZStack {
            if let review {
                ReviewView(review: review)
            }
        }
        .onAppear {
            if review == nil, let game = model.savedGames.first(where: { $0.id == gameID }) {
                review = GameReviewModel(
                    game: game, engine: model.engine, thresholds: model.catalog.tuning.review,
                    openingBook: model.catalog.openingBook)
            }
            review?.start()
        }
        .onDisappear { review?.stop() }
    }
}

/// The board with the coach line, controls, and moves: the panel sits right of the board on
/// wide screens and the moves go under it on narrow ones.
private struct ReviewView: View {
    let review: GameReviewModel
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var ply = 0

    var body: some View {
        let style = model.catalog.interface
        GeometryReader { proxy in
            if GameLayout.isWide(proxy.size, style: style.game) {
                wideLayout(style, isShort: GameLayout.barsInPanel(proxy.size, style: style.game))
            } else {
                narrowLayout(style)
            }
        }
        .padding(style.gap)
        .screenTitle(localization("review.title"), chrome: .board)
        #if os(macOS)
        .navigationSubtitle(GamesLayout.title(review.game, localization: localization))
        #endif
    }

    private var board: some View {
        let position = review.positions[ply]
        let snapshot = ReviewLayout.snapshot(
            position, lastMove: ply > 0 ? review.game.game.moves[ply - 1].move : nil,
            orientation: review.game.humanColor ?? .white)
        return BoardSceneView(snapshot: snapshot, canCancel: false) { intent in
            if case .moveFocus(let direction) = intent { go(ReviewLayout.step(for: direction)) }
        }
    }

    private var summary: some View {
        ReviewSummary(review: review)
    }

    private var coach: some View {
        ReviewCoach(review: review, ply: ply)
    }

    private var controls: some View {
        ReviewControls(ply: ply, moveCount: review.moveCount, go: go)
    }

    private func moves(_ axis: Axis.Set) -> some View {
        ReviewMoveList(review: review, ply: $ply, axis: axis)
    }

    private func go(_ step: ReviewLayout.Step) {
        ply = ReviewLayout.ply(ply, step: step, moveCount: review.moveCount)
    }

    /// On a short screen the panel scrolls and the moves run in one row, as in the narrow
    /// layout, because a vertical move list would get too little height to show a move.
    private func wideLayout(_ style: InterfaceStyle, isShort: Bool) -> some View {
        HStack(spacing: style.sectionGap) {
            board.frame(maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if isShort {
                    ScrollView {
                        VStack(spacing: style.gap) {
                            summary
                            coach
                            controls
                            moves(.horizontal)
                        }
                    }
                } else {
                    VStack(spacing: style.gap) {
                        summary
                        coach
                        moves(.vertical)
                            .frame(maxHeight: .infinity)
                            .surface(style)
                        controls
                    }
                }
            }
            .frame(width: style.game.panelWidth * style.platformScale)
        }
    }

    private func narrowLayout(_ style: InterfaceStyle) -> some View {
        VStack(spacing: style.gap) {
            board.frame(maxWidth: .infinity, maxHeight: .infinity)
            summary
            coach
            controls
            moves(.horizontal)
        }
    }
}
