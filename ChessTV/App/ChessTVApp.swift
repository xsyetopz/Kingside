import SwiftUI
import ChessCore

@main
struct ChessTVApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.settings)
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class AppContainer: ObservableObject {
    @Published var unfinishedGame: SavedLocalGame?
    @Published private(set) var hasLoadedPersistence = false
    let settings: SettingsStore
    let gameStore: GamePersistenceStore
    let engine: any ChessEngine

    init(engine: any ChessEngine = NativeSearchEngine()) {
        self.engine = engine
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let identifier = "ChessTV.UITests.\(ProcessInfo.processInfo.processIdentifier)"
            settings = SettingsStore(defaults: UserDefaults(suiteName: identifier) ?? .standard)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
            gameStore = GamePersistenceStore(directoryURL: directory)
        } else {
            settings = SettingsStore()
            gameStore = GamePersistenceStore()
        }
        Task { [weak self, gameStore = self.gameStore] in
            let game = await gameStore.unfinishedGame()
            self?.unfinishedGame = game
            self?.hasLoadedPersistence = true
        }
    }

    func makeGameViewModel() -> GameViewModel {
        GameViewModel(engine: engine, settings: settings, store: gameStore)
    }

    func refreshSavedGame() {
        Task { [weak self, gameStore = self.gameStore] in self?.unfinishedGame = await gameStore.unfinishedGame() }
    }
}
