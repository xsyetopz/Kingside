import SwiftUI
import ChessCore

/// Route destination for `.archive`: finished local games, newest first. Selecting a game opens
/// Game Review; the context menu (press and hold) deletes it.
struct ArchiveView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: SettingsStore
    @State private var games: [SavedGame]?

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Game Archive")
                .font(ChessFont.title)
                .foregroundStyle(ChessTheme.textPrimary)
            if let games {
                if games.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(games) { game in
                                NavigationLink(value: AppRoute.review(game.id)) {
                                    ArchiveRow(game: game, theme: settings.value.boardTheme)
                                }
                                .buttonStyle(.panelCard)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(game) }
                                }
                            }
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 30)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessScreen()
        .task { await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray")
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(ChessTheme.textMuted)
            Text("No finished games yet")
                .font(ChessFont.heading)
                .foregroundStyle(ChessTheme.textPrimary)
            Text("Games you finish against bots or friends are kept here for review.")
                .font(ChessFont.bodyRegular)
                .foregroundStyle(ChessTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        games = await container.gameStore.allGames().filter(\.isFinished)
    }

    private func delete(_ game: SavedGame) {
        Task {
            try? await container.gameStore.delete(id: game.id)
            await reload()
        }
    }
}

/// One archive entry: final position, opponent, result, reason, time control, length and date.
struct ArchiveRow: View {
    let game: SavedGame
    var theme: BoardTheme = .green

    /// Results are shown for the human in bot games and for White in pass-and-play.
    private var perspective: PieceColor { game.humanColor ?? .white }
    private var opponent: PlayerInfo { game.player(perspective.opponent) }

    var body: some View {
        HStack(spacing: 32) {
            ChessBoardDisplay.thumbnail(
                game.game.position,
                lastMove: game.game.moves.last?.move,
                isFlipped: perspective == .black,
                theme: theme,
                size: 150
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            ReviewPlayerAvatar(player: opponent, size: 80)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(ChessFont.subheading)
                    .foregroundStyle(ChessTheme.textPrimary)
                    .lineLimit(1)
                Text(game.termination.map { "\(resultWord) \($0.reasonText)" } ?? resultWord)
                    .font(ChessFont.bodyRegular)
                    .foregroundStyle(ChessTheme.textSecondary)
            }
            Spacer(minLength: 20)
            resultIcon
            VStack(alignment: .trailing, spacing: 8) {
                Label(game.timeControl.label, systemImage: "timer")
                Text(verbatim: (game.game.moves.count + 1) / 2 == 1 ? "1 move" : "\((game.game.moves.count + 1) / 2) moves")
                Text(game.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(ChessFont.caption)
            .foregroundStyle(ChessTheme.textSecondary)
            .frame(width: 260, alignment: .trailing)
        }
        .padding(20)
    }

    private var title: String {
        let name = opponent.rating.map { "\(opponent.name) (\($0))" } ?? opponent.name
        return game.mode.botID == nil ? "\(game.white.name) vs \(game.black.name)" : "vs \(name)"
    }

    private var outcome: (symbol: String, color: Color) {
        guard let winner = game.result.winner else { return ("equal", ChessTheme.draw) }
        return winner == perspective ? ("plus", ChessTheme.win) : ("minus", ChessTheme.loss)
    }

    private var resultWord: String {
        switch game.result {
        case .draw, .ongoing: "Draw"
        case .whiteWon, .blackWon: "\(game.player(game.result.winner ?? .white).name) won"
        }
    }

    private var resultIcon: some View {
        Image(systemName: outcome.symbol)
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(outcome.color, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Bot avatar from the roster, or initials for a human player.
struct ReviewPlayerAvatar: View {
    let player: PlayerInfo
    var size: CGFloat = 72

    var body: some View {
        if let id = player.botID, let bot = BotRoster.bot(id: id) {
            bot.avatar(size: size)
        } else {
            AvatarView(name: player.name, size: size)
        }
    }
}
