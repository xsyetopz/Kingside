import SwiftUI

enum AppRoute: Hashable {
    case newGame
    case resumeGame
    case recentGames
    case puzzles
    case players
    case settings
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var path: [AppRoute] = []
    @State private var handledInitialRestore = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .newGame: NewGameView(path: $path, resumesSavedGame: false)
                    case .resumeGame: NewGameView(path: $path, resumesSavedGame: true)
                    case .recentGames: RecentGamesView()
                    case .puzzles: PuzzleLibraryView()
                    case .players: PlayerConnectionView()
                    case .settings: SettingsView()
                    }
                }
        }
        .tint(ChessTheme.accent)
        .onAppear(perform: restoreUnfinishedGameIfNeeded)
        .onChange(of: container.hasLoadedPersistence) { _, _ in
            restoreUnfinishedGameIfNeeded()
        }
    }

    private func restoreUnfinishedGameIfNeeded() {
        guard container.hasLoadedPersistence, !handledInitialRestore else { return }
        handledInitialRestore = true
        if container.unfinishedGame != nil, path.isEmpty {
            path.append(.resumeGame)
        }
    }
}
