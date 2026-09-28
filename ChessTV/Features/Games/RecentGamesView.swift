import SwiftUI
import ChessCore

@MainActor
final class RecentGamesViewModel: ObservableObject {
    @Published private(set) var games: [SavedLocalGame] = []
    func load(from store: GamePersistenceStore) {
        Task { games = await store.allGames() }
    }
}

struct RecentGamesView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var viewModel = RecentGamesViewModel()

    var body: some View {
        Group {
            if viewModel.games.isEmpty {
                ContentUnavailableView("No recent games", systemImage: "checkerboard.rectangle", description: Text("Your local games will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(viewModel.games) { saved in
                            HStack(spacing: 25) {
                                Image(systemName: saved.isFinished ? "checkmark.seal" : "pause.circle")
                                    .font(.system(size: 42)).foregroundStyle(ChessTheme.accent)
                                VStack(alignment: .leading) {
                                    Text(saved.isFinished ? resultText(saved.game.position.outcome) : "Unfinished game")
                                        .font(.title2.bold())
                                    Text("\(saved.movesDescription) · \(saved.difficulty.rawValue.capitalized)")
                                        .font(.headline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(saved.updatedAt, style: .relative).font(.headline)
                            }
                            .padding(28)
                            .background(ChessTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }.padding(60)
                }
            }
        }
        .navigationTitle("Recent Games")
        .chessScreen()
        .onAppear { viewModel.load(from: container.gameStore) }
    }

    private func resultText(_ outcome: GameOutcome) -> String {
        switch outcome {
        case .checkmate(let winner): "\(winner.rawValue.capitalized) won"
        case .stalemate: "Stalemate"
        case .drawFiftyMove: "Draw"
        case .ongoing: "Game in progress"
        }
    }
}

private extension SavedLocalGame {
    var movesDescription: String { "\(game.moves.count) moves" }
}
