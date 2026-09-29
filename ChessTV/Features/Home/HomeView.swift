import SwiftUI
import ChessCore

/// Home: a navigation sidebar on the left and the "Play Chess" hero on the right.
struct HomeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: SettingsStore
    @Binding var path: [AppRoute]
    @FocusState private var focused: HomeFocus?
    @State private var puzzleProgress = PuzzleProgress()

    private enum HomeFocus: Hashable {
        case continueGame, playBots, playFriend, puzzles
    }

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(path: $path)
            mainArea
        }
        .background(ChessTheme.background.ignoresSafeArea())
        .defaultFocus($focused, container.unfinishedGame == nil ? .playBots : .continueGame)
        .onAppear {
            container.refreshSavedGame()
            puzzleProgress = PuzzleProgressStore().progress
            focused = container.unfinishedGame == nil ? .playBots : .continueGame
        }
        .onChange(of: container.unfinishedGame?.id) { _, id in
            // The saved game loads asynchronously; move focus to it once it arrives.
            if id != nil, focused == nil || focused == .playBots { focused = .continueGame }
        }
    }

    private var mainArea: some View {
        VStack(alignment: .leading, spacing: 36) {
            if let saved = container.unfinishedGame {
                continueCard(saved)
            }

            Text("Play Chess")
                .font(ChessFont.title)
                .foregroundStyle(ChessTheme.textPrimary)

            HStack(alignment: .top, spacing: 60) {
                ChessBoardDisplay.thumbnail(
                    .initial,
                    theme: settings.value.boardTheme,
                    size: container.unfinishedGame == nil ? 600 : 460
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                .accessibilityHidden(true)

                VStack(spacing: 28) {
                    heroButton(
                        .playBots, route: .playBots, title: "Play Bots",
                        subtitle: "Challenge a bot personality", icon: "cpu", isPrimary: true,
                        identifier: "home.playBots"
                    )
                    heroButton(
                        .playFriend, route: .playFriend, title: "Play a Friend",
                        subtitle: "Pass and play", icon: "person.2.fill", isPrimary: false,
                        identifier: "home.playFriend"
                    )
                    heroButton(
                        .puzzles, route: .puzzles, title: "Puzzles",
                        subtitle: "Rating \(puzzleProgress.rating)", icon: "puzzlepiece.fill", isPrimary: false,
                        identifier: "home.puzzles"
                    )
                }
                .frame(width: 640)
                .focusSection()
            }

            Spacer(minLength: 0)

            statsStrip
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func continueCard(_ saved: SavedGame) -> some View {
        Button { path.append(.game(.saved(saved))) } label: {
            HStack(spacing: 28) {
                ChessBoardDisplay.thumbnail(
                    saved.game.position,
                    lastMove: saved.game.moves.last?.move,
                    isFlipped: saved.humanColor == .black,
                    theme: settings.value.boardTheme,
                    size: 120
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    Text(continueTitle(saved))
                        .font(ChessFont.heading)
                        .lineLimit(1)
                    Text("Move \(saved.game.moves.count / 2 + 1) · \(saved.game.position.sideToMove == .white ? "White" : "Black") to move")
                        .font(ChessFont.caption)
                        .foregroundStyle(ChessTheme.textSecondary)
                }
                Spacer(minLength: 20)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(ChessTheme.primary)
            }
            .frame(width: 1300, alignment: .leading)
        }
        .buttonStyle(PanelCardStyle(padding: 22))
        .focused($focused, equals: .continueGame)
        .accessibilityIdentifier("home.continue")
    }

    private func continueTitle(_ saved: SavedGame) -> String {
        if let human = saved.humanColor {
            return "Continue game vs \(saved.player(human.opponent).name)"
        }
        return "Continue \(saved.white.name) vs \(saved.black.name)"
    }

    @ViewBuilder
    private func heroButton(
        _ focus: HomeFocus, route: AppRoute, title: String, subtitle: String,
        icon: String, isPrimary: Bool, identifier: String
    ) -> some View {
        let button = Button { path.append(route) } label: {
            HStack(spacing: 26) {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .bold))
                    .frame(width: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(ChessFont.rounded(40, weight: .heavy))
                    Text(subtitle)
                        .font(ChessFont.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
        Group {
            if isPrimary {
                button.buttonStyle(.chessPrimary(fullWidth: true))
            } else {
                button.buttonStyle(.chessSecondary(fullWidth: true))
            }
        }
        .focused($focused, equals: focus)
        .accessibilityIdentifier(identifier)
    }

    private var statsStrip: some View {
        let rushBest = PuzzleRushMode.allCases.map { puzzleProgress.rushBest[$0.rawValue] ?? 0 }.max() ?? 0
        return HStack(spacing: 60) {
            StatItem(icon: "puzzlepiece.fill", title: "Puzzle Rating", value: "\(puzzleProgress.rating)")
            StatItem(icon: "flame.fill", title: "Best Streak", value: "\(puzzleProgress.bestStreak)")
            StatItem(icon: "bolt.fill", title: "Puzzle Rush Best", value: rushBest > 0 ? "\(rushBest)" : "–")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatItem: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(ChessTheme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(ChessFont.rounded(34, weight: .heavy))
                    .foregroundStyle(ChessTheme.textPrimary)
                Text(title)
                    .font(ChessFont.caption)
                    .foregroundStyle(ChessTheme.textMuted)
            }
        }
    }
}

/// The left navigation column: pawn logo, wordmark and focusable section rows.
private struct HomeSidebar: View {
    @Binding var path: [AppRoute]

    private struct Item: Identifiable {
        let title: String
        let icon: String
        let route: AppRoute
        var id: String { title }
    }

    private let items = [
        Item(title: "Play", icon: "play.fill", route: .playBots),
        Item(title: "Puzzles", icon: "puzzlepiece.fill", route: .puzzles),
        Item(title: "Archive", icon: "clock.arrow.circlepath", route: .archive),
        Item(title: "Settings", icon: "gearshape.fill", route: .settings)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PieceSet.cburnett.image(for: Piece(type: .pawn, color: .white))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Text("Chess")
                    .font(ChessFont.rounded(48, weight: .heavy))
                    .foregroundStyle(ChessTheme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Chess")

            ForEach(items) { item in
                Button { path.append(item.route) } label: {
                    Label(item.title, systemImage: item.icon)
                        .labelStyle(.alignedIcon(width: 44))
                }
                .buttonStyle(SidebarRowStyle())
                .accessibilityIdentifier("sidebar.\(item.title.lowercased())")
            }

            Spacer()
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
        .frame(width: 300, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ChessTheme.panel.ignoresSafeArea())
        .focusSection()
    }
}

private struct SidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarRow(configuration: configuration)
    }

    private struct SidebarRow: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(ChessFont.body)
                .foregroundStyle(isFocused ? ChessTheme.textPrimary : ChessTheme.textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isFocused ? ChessTheme.focusSurface : .clear,
                    in: RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous)
                )
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(ChessTheme.primary)
                        .frame(width: 5, height: 36)
                        .opacity(isFocused ? 1 : 0)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : isFocused ? 1.04 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
        }
    }
}
