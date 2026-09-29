import SwiftUI

// Right-hand game panel: header (bot chat, or "Pass and Play" with the time control),
// move list, status line, and the action bar (post-game buttons once the game is over).

struct GamePanel: View {
    @ObservedObject var viewModel: GameViewModel
    var focus: FocusState<GameFocusTarget?>.Binding
    let onAction: (GameAction) -> Void
    let onNewGame: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GamePanelHeader(viewModel: viewModel)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ChessTheme.raised.opacity(0.5))
            MovesPanel(rows: viewModel.moveRows)
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity)
            Divider().overlay(ChessTheme.raised)
            Text(viewModel.statusText)
                .font(ChessFont.subheading)
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .accessibilityLabel("Game status: \(viewModel.statusText)")
            Group {
                if viewModel.isGameOver {
                    PostGameBar(
                        gameID: viewModel.id,
                        newGameTitle: newGameTitle,
                        focus: focus,
                        onRematch: viewModel.rematch,
                        onNewGame: onNewGame
                    )
                } else {
                    ActionBar(viewModel: viewModel, focus: focus, onAction: onAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(ChessTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous))
    }

    var newGameTitle: String { viewModel.isPassAndPlay ? "New Game" : "New Bot" }

    private var statusColor: Color {
        let position = viewModel.game.position
        if !viewModel.isGameOver && position.isInCheck(position.sideToMove) { return ChessTheme.danger }
        return ChessTheme.textPrimary
    }
}

private struct GamePanelHeader: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        if let bot = viewModel.bot {
            HStack(alignment: .top, spacing: 20) {
                bot.avatar(size: 96)
                VStack(alignment: .leading, spacing: 10) {
                    if let message = viewModel.botMessage, !message.isEmpty {
                        SpeechBubble(text: message)
                    } else {
                        Text(bot.name).font(ChessFont.heading)
                        Text(verbatim: "\(bot.rating)  ·  \(viewModel.timeControl.label)")
                            .font(ChessFont.bodyRegular)
                            .foregroundStyle(ChessTheme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            }
        } else {
            HStack(spacing: 20) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(ChessTheme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pass and Play").font(ChessFont.heading)
                    Text(viewModel.timeControl.label)
                        .font(ChessFont.bodyRegular)
                        .foregroundStyle(ChessTheme.textMuted)
                }
            }
        }
    }
}
