import SwiftUI
import ChessCore

// Game-over modal drawn over the dimmed board: result title and reason, both players with
// the winner crowned, the bot's last chat line, and Game Review / Rematch / New Game.
// The X button or Back closes it so the final position can be studied.

struct GameOverCard: View {
    @ObservedObject var viewModel: GameViewModel
    let newGameTitle: String
    let onNewGame: () -> Void
    let onClose: () -> Void
    @FocusState private var focus: GameFocusTarget?

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text(viewModel.resultTitle)
                    .font(ChessFont.title)
                    .foregroundStyle(titleColor)
                if !viewModel.resultReason.isEmpty {
                    Text(viewModel.resultReason)
                        .font(ChessFont.body)
                        .foregroundStyle(ChessTheme.textSecondary)
                }
            }
            HStack(spacing: 36) {
                FinalPlayer(info: viewModel.player(.white), isWinner: winner == .white)
                Text("vs").font(ChessFont.heading).foregroundStyle(ChessTheme.textMuted)
                FinalPlayer(info: viewModel.player(.black), isWinner: winner == .black)
            }
            if let bot = viewModel.bot, let message = viewModel.botMessage, !message.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    bot.avatar(size: 56)
                    SpeechBubble(text: message, font: ChessFont.bodyRegular)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 16) {
                NavigationLink(value: AppRoute.review(viewModel.id)) { Text("Game Review") }
                    .buttonStyle(.chessPrimary(icon: "star.fill", fullWidth: true))
                    .focused($focus, equals: .review)
                HStack(spacing: 16) {
                    Button("Rematch", action: viewModel.rematch)
                        .buttonStyle(.chessSecondary(fullWidth: true))
                        .focused($focus, equals: .rematch)
                    Button(newGameTitle, action: onNewGame)
                        .buttonStyle(.chessSecondary(fullWidth: true))
                        .focused($focus, equals: .newGame)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 56)
        .padding(.bottom, 40)
        .frame(width: 720)
        .background(ChessTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 28, weight: .bold))
            }
            .buttonStyle(PanelCardStyle(padding: 16))
            .padding(16)
            .accessibilityLabel("Close")
        }
        .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        .focusSection()
        .onAppear { focus = .review }
        .onExitCommand(perform: onClose)
    }

    private var winner: PieceColor? { viewModel.result.winner }

    private var titleColor: Color {
        guard let winner else { return ChessTheme.textPrimary }
        guard let human = viewModel.humanColor else { return ChessTheme.primary }
        return winner == human ? ChessTheme.win : ChessTheme.lossBright
    }
}

private struct FinalPlayer: View {
    let info: PlayerInfo
    let isWinner: Bool

    var body: some View {
        VStack(spacing: 10) {
            PlayerAvatar(info: info, size: 112)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ChessTheme.win, lineWidth: isWinner ? 6 : 0)
                        .padding(-6)
                }
                .overlay(alignment: .top) {
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                            .offset(y: -38)
                    }
                }
            Text(info.name)
                .font(ChessFont.body.weight(.bold))
                .lineLimit(1)
            Text(info.rating.map(String.init) ?? " ")
                .font(ChessFont.caption)
                .foregroundStyle(ChessTheme.textMuted)
        }
        .frame(width: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(info.name + (isWinner ? ", winner" : ""))
    }
}
