import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var path: [AppRoute]
    @FocusState private var focused: AppRoute?

    private struct Card: Identifiable {
        let route: AppRoute
        let title: String
        let subtitle: String
        let icon: String
        var id: AppRoute { route }
    }

    private var cards: [Card] {
        var result: [Card] = []
        if container.unfinishedGame != nil {
            result.append(Card(route: .resumeGame, title: "Continue Game", subtitle: "Return to your board", icon: "play.circle.fill"))
        }
        result += [
            Card(route: .newGame, title: "Play Computer", subtitle: "Your board. Your pace.", icon: "cpu"),
            Card(route: .puzzles, title: "Puzzles", subtitle: "Find the winning idea", icon: "puzzlepiece.extension"),
            Card(route: .recentGames, title: "Recent Games", subtitle: "Resume or replay", icon: "clock.arrow.circlepath"),
            Card(route: .players, title: "Players", subtitle: "Connect a public Chess.com profile", icon: "person.2"),
            Card(route: .settings, title: "Settings", subtitle: "Make the board yours", icon: "gearshape")
        ]
        return result
    }

    private var featuredCards: [Card] {
        Array(cards.prefix(container.unfinishedGame == nil ? 1 : 2))
    }

    private var utilityCards: [Card] {
        Array(cards.dropFirst(featuredCards.count))
    }

    var body: some View {
        ZStack {
            Image("HomeWallpaper")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [
                    ChessTheme.background.opacity(0.96),
                    ChessTheme.background.opacity(0.70),
                    ChessTheme.background.opacity(0.26)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            LinearGradient(
                colors: [.black.opacity(0.18), .clear, .black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CHESS")
                            .font(.system(size: 62, weight: .heavy, design: .rounded))
                        Text("CHESS, BUILT FOR THE BIG SCREEN")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(ChessTheme.accent)
                    }

                    Spacer(minLength: 36)

                    VStack(spacing: 22) {
                        HStack(spacing: 22) {
                            ForEach(featuredCards) { card in
                                homeButton(card, isFeatured: true)
                            }
                        }

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible())],
                            spacing: 22
                        ) {
                            ForEach(utilityCards) { card in
                                homeButton(card, isFeatured: false)
                            }
                        }
                    }
                    .padding(26)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
                    .focusSection()
                }
                .frame(width: 920)

                Spacer(minLength: 280)
            }
            .padding(.leading, 76)
            .padding(.trailing, 70)
            .padding(.top, 48)
            .padding(.bottom, 62)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            container.refreshSavedGame()
            focused = container.unfinishedGame == nil ? .newGame : .resumeGame
        }
    }

    private func homeButton(_ card: Card, isFeatured: Bool) -> some View {
        Button { path.append(card.route) } label: {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [ChessTheme.accent.opacity(0.30), ChessTheme.accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.46), radius: 7, y: 6)

                    Image(systemName: card.icon)
                        .font(.system(size: isFeatured ? 34 : 29, weight: .bold))
                        .foregroundStyle(ChessTheme.accent)
                }
                .frame(width: isFeatured ? 70 : 62, height: isFeatured ? 70 : 62)

                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title)
                        .font(isFeatured ? .title2.bold() : .title3.bold())
                        .lineLimit(1)
                    Text(card.subtitle)
                        .font(isFeatured ? .headline : .subheadline.bold())
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline.bold())
                    .foregroundStyle(.white.opacity(0.46))
            }
            .frame(maxWidth: .infinity, minHeight: isFeatured ? 86 : 72, alignment: .leading)
        }
        .buttonStyle(RaisedHomeButtonStyle(isFeatured: isFeatured))
        .focused($focused, equals: card.route)
        .accessibilityLabel("\(card.title). \(card.subtitle)")
    }
}

private struct RaisedHomeButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    let isFeatured: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, isFeatured ? 24 : 20)
            .padding(.vertical, isFeatured ? 18 : 15)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 0.018, green: 0.055, blue: 0.055))
                        .offset(y: 11)

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isFocused
                                    ? [Color(red: 0.13, green: 0.29, blue: 0.28), Color(red: 0.055, green: 0.12, blue: 0.15)]
                                    : [ChessTheme.surfaceRaised.opacity(0.96), ChessTheme.surface.opacity(0.94)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(.white.opacity(isFocused ? 0.30 : 0.13))
                                .frame(height: 2)
                                .padding(.horizontal, 24)
                                .padding(.top, 3)
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isFocused ? ChessTheme.accent : .white.opacity(0.12),
                        lineWidth: isFocused ? 3 : 1
                    )
            }
            .shadow(color: isFocused ? ChessTheme.accent.opacity(0.34) : .black.opacity(0.50), radius: isFocused ? 24 : 12, y: isFocused ? 12 : 9)
            .offset(y: configuration.isPressed ? 7 : isFocused ? -6 : 0)
            .scaleEffect(isFocused ? 1.035 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isFocused)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
