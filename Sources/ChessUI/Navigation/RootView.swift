import ChessContent
import SwiftUI

/// The app's root: a tab view on iOS and tvOS, a sidebar on macOS.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var selection: AppSection = .play

    var body: some View {
        content
            .task {
                model.signInAtLaunch()
                await model.reloadGames()
            }
            .sheet(isPresented: Binding(get: { model.showsWelcome }, set: { if !$0 { model.finishWelcome() } })) {
                WelcomeSheet { selection = .account }
            }
            .sheet(isPresented: Binding(
                get: { model.gameCenter.pendingSignInViewController != nil },
                set: { if !$0 { model.gameCenter.pendingSignInViewController = nil } })
            ) {
                if let viewController = model.gameCenter.pendingSignInViewController {
                    GameCenterSignInView(viewController: viewController)
                }
            }
    }

    #if os(macOS)
    @ViewBuilder private var content: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding($selection)) { section in
                Label(localization(section.titleKey), systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            SectionStack(section: selection)
                .id(selection)
        }
    }
    #else
    @ViewBuilder private var content: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                SectionStack(section: section)
                    .tabItem { Label(localization(section.titleKey), systemImage: section.systemImage) }
                    .tag(section)
            }
        }
    }
    #endif
}

/// One section's navigation stack and the screens it can push.
struct SectionStack: View {
    let section: AppSection
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            SectionHome(section: section)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .game(let launch):
                        GameScreen(launch: launch)
                    case .bots:
                        PlayBotsScreen()
                    case .passAndPlay:
                        PassAndPlayScreen()
                    case .ratedPuzzles:
                        RatedPuzzleScreen()
                    case .puzzleRush:
                        PuzzleRushScreen()
                    case .dailyPuzzle(let day):
                        DailyPuzzleScreen(day: day)
                    case .review(let id):
                        ReviewScreen(gameID: id)
                    case .chessComLink:
                        ChessComLinkScreen()
                    }
                }
        }
    }
}

private struct SectionHome: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .play: PlayHome()
        case .puzzles: PuzzlesHome()
        case .games: GamesHome()
        case .account: AccountHome()
        #if !os(macOS)
        case .settings: SettingsHome()
        #endif
        }
    }
}

