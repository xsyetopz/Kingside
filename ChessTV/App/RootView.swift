import SwiftUI

enum AppRoute: Hashable {
    case playBots
    case playFriend
    case game(GameLaunch)
    case puzzles
    case settings
    case archive
    case review(UUID)
}

struct RootView: View {
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .playBots: PlayBotsView(path: $path)
                    case .playFriend: PlayFriendView(path: $path)
                    case .game(let launch): GameScreen(launch: launch)
                    case .puzzles: PuzzlesHubView()
                    case .settings: SettingsView()
                    case .archive: ArchiveView()
                    case .review(let id): ReviewScreen(gameID: id)
                    }
                }
        }
        .tint(ChessTheme.accent)
    }
}
