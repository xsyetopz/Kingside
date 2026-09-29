import SwiftUI
import ChessCore

/// Route destination for `.game(launch)`: owns the view model and its lifecycle.
struct GameScreen: View {
    let launch: GameLaunch
    @EnvironmentObject private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GameViewModel?

    var body: some View {
        Group {
            if let viewModel {
                GameView(viewModel: viewModel) { dismiss() }
            } else {
                Color.clear
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if viewModel == nil { viewModel = container.makeGameViewModel(launch: launch) }
            viewModel?.activate()
        }
        .onDisappear { viewModel?.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel?.activate() } else { viewModel?.deactivate() }
        }
    }
}


/// In-game screen: player bars around the board on the left, the game panel on the right.
/// Focus: the board starts focused; moving right off its edge or pressing Back with nothing
/// selected focuses the panel; moving left from the panel returns to the board; Back on the
/// panel leaves the screen (the view model saves on deactivate).
struct GameView: View {
    @ObservedObject var viewModel: GameViewModel
    let onExit: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @FocusState private var focus: GameFocusTarget?
    @Namespace private var focusScope
    @State private var confirmsResign = false
    @State private var showsGameOver = false

    private static let boardSide: CGFloat = 896
    private static let panelWidth: CGFloat = 640

    var body: some View {
        HStack(spacing: 40) {
            VStack(spacing: 8) {
                PlayerBar(slot: viewModel.topPlayer, viewModel: viewModel)
                board
                PlayerBar(slot: viewModel.bottomPlayer, viewModel: viewModel)
            }
            .frame(width: Self.boardSide)
            .focusSection()

            GamePanel(viewModel: viewModel, focus: $focus, onAction: perform, onNewGame: onExit)
                .frame(width: Self.panelWidth)
                .frame(maxHeight: .infinity)
                .disabled(showsGameOver)
                .focusSection()
                .onExitCommand(perform: onExit)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .chessScreen()
        .focusScope(focusScope)
        .onAppear { showsGameOver = viewModel.isGameOver }
        .onChange(of: viewModel.isGameOver) { _, isOver in
            withAnimation(.easeOut(duration: 0.25)) { showsGameOver = isOver }
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmsResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { viewModel.resign() }
            Button("Keep Playing", role: .cancel) {}
        }
        .alert(drawOfferTitle, isPresented: drawOfferShown) {
            Button("Accept Draw") { viewModel.acceptDraw() }
            Button("Decline", role: .cancel) { viewModel.declineDraw() }
        } message: {
            Text("Hand the remote to the other player to answer.")
        }
    }

    private var board: some View {
        ChessBoardView(
            position: viewModel.game.position,
            interaction: viewModel.board,
            showLegalMoves: settings.value.showLegalMoves,
            showCoordinates: settings.value.showCoordinates,
            highlightLastMove: settings.value.highlightLastMove,
            animateMoves: settings.value.moveAnimation,
            boardTheme: settings.value.boardTheme,
            pieceSet: settings.value.pieceSet,
            arrows: viewModel.hintArrow.map { [$0] } ?? [],
            isInputEnabled: isBoardInputEnabled,
            onSelect: viewModel.select,
            onCancel: { if !viewModel.cancelSelection() { focusPanel() } },
            onMoveOffEdge: { direction in
                guard direction == .right else { return false }
                focusPanel()
                return true
            }
        )
        .frame(width: Self.boardSide, height: Self.boardSide)
        .focused($focus, equals: .board)
        .prefersDefaultFocus(in: focusScope)
        .overlay {
            if let move = viewModel.pendingPromotion.first {
                PromotionPickerOverlay(
                    square: move.to,
                    color: viewModel.game.position[move.from]?.color ?? viewModel.game.position.sideToMove,
                    isFlipped: viewModel.board.isFlipped,
                    onPick: viewModel.choosePromotion,
                    onCancel: { viewModel.cancelSelection() }
                )
            }
        }
        .overlay {
            if showsGameOver {
                ZStack {
                    Color.black.opacity(0.55)
                    GameOverCard(
                        viewModel: viewModel,
                        newGameTitle: viewModel.isPassAndPlay ? "New Game" : "New Bot",
                        onNewGame: onExit,
                        onClose: { showsGameOver = false }
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private var isBoardInputEnabled: Bool {
        viewModel.pendingPromotion.isEmpty && viewModel.pendingDrawOffer == nil
            && !confirmsResign && !showsGameOver
    }

    /// Focuses the first enabled panel button.
    private func focusPanel() {
        if viewModel.isGameOver {
            focus = .review
        } else if let action = GameAction.allCases.first(where: { $0.isEnabled(in: viewModel) }) {
            focus = .action(action)
        }
    }

    private func perform(_ action: GameAction) {
        switch action {
        case .resign: confirmsResign = true
        case .draw: viewModel.offerDraw()
        case .takeback: viewModel.takeback()
        case .hint: viewModel.requestHint()
        case .flip: viewModel.flipBoard()
        }
    }

    private var drawOfferTitle: String {
        guard let offering = viewModel.pendingDrawOffer else { return "" }
        return "\(offering == .white ? "White" : "Black") offers a draw"
    }

    private var drawOfferShown: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDrawOffer != nil },
            set: { if !$0, viewModel.pendingDrawOffer != nil { viewModel.declineDraw() } }
        )
    }
}
