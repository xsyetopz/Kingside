import SwiftUI

@MainActor
final class PlayerConnectionViewModel: ObservableObject {
    @Published var username = ""
    @Published private(set) var player: Player?
    @Published private(set) var games: [OnlineGame] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private let api: any ChessAPI
    private let defaults: UserDefaults

    init(api: any ChessAPI = ChessComAPIClient(), defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        username = defaults.string(forKey: "ChessTV.connectedPublicUsername") ?? ""
    }

    func connect() {
        let requested = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                async let loadedPlayer = api.getPlayer(username: requested)
                async let loadedGames = api.getGames(username: requested)
                player = try await loadedPlayer
                games = try await loadedGames
                games.sort { ($0.endTime ?? 0) > ($1.endTime ?? 0) }
                defaults.set(player?.username, forKey: "ChessTV.connectedPublicUsername")
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Unable to load this player."
            }
            isLoading = false
        }
    }

    func disconnect() {
        player = nil
        games = []
        username = ""
        defaults.removeObject(forKey: "ChessTV.connectedPublicUsername")
    }
}

struct PlayerConnectionView: View {
    @StateObject private var viewModel = PlayerConnectionViewModel()

    var body: some View {
        VStack(spacing: 30) {
            Text("Chess.com Profile").font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Connect public profile data by username. Chess never asks for your Chess.com password.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                TextField("Chess.com username", text: $viewModel.username)
                    .textContentType(.username)
                    .frame(width: 520)
                Button("Connect", action: viewModel.connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.username.isEmpty || viewModel.isLoading)
            }
            if viewModel.isLoading { ProgressView("Loading profile…") }
            if let player = viewModel.player {
                VStack(spacing: 12) {
                    Text(player.name ?? player.username).font(.largeTitle.bold())
                    Text("@\(player.username) · \(viewModel.games.count) recent games loaded")
                        .font(.title3).foregroundStyle(.secondary)
                    Button("Disconnect", role: .destructive, action: viewModel.disconnect)
                }
                .padding(34)
                .background(ChessTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(ChessTheme.danger).font(.title3)
                Button("Retry", action: viewModel.connect)
            }
            Spacer()
            Text("Full Chess.com sign-in requires Chess.com OAuth approval and an issued client ID. The integration boundary is ready, but credentials are intentionally not bundled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 820)
        }
        .padding(70)
        .navigationTitle("Players")
        .chessScreen()
    }
}
