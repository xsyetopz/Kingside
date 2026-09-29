import SwiftUI

// Bottom of the game panel. While playing: icon buttons with small labels (Resign, Draw,
// Takeback, Hint, Flip), each disabled when it does not apply. After the game: a green
// "Game Review" button plus Rematch and New Game / New Bot.

/// Focus targets on the game screen, shared by the board, panel and game-over card.
enum GameFocusTarget: Hashable {
    case board
    case action(GameAction)
    case review
    case rematch
    case newGame
}

enum GameAction: CaseIterable, Hashable {
    case resign, draw, takeback, hint, flip

    var title: String {
        switch self {
        case .resign: "Resign"
        case .draw: "Draw"
        case .takeback: "Takeback"
        case .hint: "Hint"
        case .flip: "Flip"
        }
    }

    /// SF Symbol; nil for Draw, which shows a "½" glyph.
    var symbol: String? {
        switch self {
        case .resign: "flag.fill"
        case .draw: nil
        case .takeback: "arrow.uturn.backward"
        case .hint: "lightbulb.fill"
        case .flip: "arrow.up.arrow.down"
        }
    }

    @MainActor
    func isEnabled(in viewModel: GameViewModel) -> Bool {
        switch self {
        case .resign, .draw: !viewModel.isGameOver
        case .takeback: viewModel.canTakeback
        case .hint: viewModel.canMove && !viewModel.isLoadingHint
        case .flip: true
        }
    }
}

struct ActionBar: View {
    @ObservedObject var viewModel: GameViewModel
    var focus: FocusState<GameFocusTarget?>.Binding
    let onAction: (GameAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GameAction.allCases, id: \.self) { action in
                Button { onAction(action) } label: {
                    VStack(spacing: 6) {
                        Group {
                            if let symbol = action.symbol {
                                Image(systemName: symbol)
                            } else {
                                Text("½")
                            }
                        }
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .frame(height: 40)
                        Text(action.title).font(ChessFont.caption)
                    }
                }
                .buttonStyle(ActionIconButtonStyle())
                .disabled(!action.isEnabled(in: viewModel))
                .focused(focus, equals: .action(action))
                .accessibilityLabel(action == .draw ? "Offer draw" : action.title)
            }
        }
    }
}

struct PostGameBar: View {
    let gameID: UUID
    let newGameTitle: String
    var focus: FocusState<GameFocusTarget?>.Binding
    let onRematch: () -> Void
    let onNewGame: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            NavigationLink(value: AppRoute.review(gameID)) { Text("Game Review") }
                .buttonStyle(.chessPrimary(icon: "star.fill", fullWidth: true))
                .focused(focus, equals: .review)
            HStack(spacing: 16) {
                Button("Rematch", action: onRematch)
                    .buttonStyle(.chessSecondary(icon: "arrow.triangle.2.circlepath", fullWidth: true))
                    .focused(focus, equals: .rematch)
                Button(newGameTitle, action: onNewGame)
                    .buttonStyle(.chessSecondary(icon: "plus", fullWidth: true))
                    .focused(focus, equals: .newGame)
            }
        }
    }
}

/// Compact square button: icon over a small label, lit up while focused.
private struct ActionIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionIconButton(configuration: configuration)
    }
}

private struct ActionIconButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(isFocused ? ChessTheme.textPrimary : ChessTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isFocused ? ChessTheme.focusSurface : ChessTheme.raised, in: shape)
            .overlay { shape.strokeBorder(.white, lineWidth: isFocused ? 4 : 0) }
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : isFocused ? 1.08 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 14, y: 8)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
