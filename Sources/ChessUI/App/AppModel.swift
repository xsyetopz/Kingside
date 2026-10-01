import ChessComLink
import ChessContent
import ChessCore
import ChessFeedback
import ChessOnline
import ChessPlay
import Foundation
import HTTPSupport
import LichessLink
import Observation

/// The composition root: builds the stores, engine, feedback, and clients once, and makes the
/// sessions that screens use. Screens read it from the environment.
@preconcurrency
@Observable
@MainActor
public final class AppModel {
  public let catalog: ContentCatalog
  public let localization: Localization
  public let settings: SettingsStore
  public let puzzleProgress: PuzzleProgressStore
  let gameStore: GamePersistenceStore
  public let engine: ChessEngine
  /// Shared by every review this model opens, so a game is analysed once per launch.
  let reviewAnalyses = ReviewAnalysisCache()
  public let chessCom: ChessComClient
  public let lichess: LichessAccountModel
  /// The OAuth calls of the Lichess browser sign-in.
  let lichessOAuth: LichessOAuth
  let gameCenter: GameCenterAccount
  /// False under `--uitesting`: no Game Center sign-in and no welcome sheet.
  let usesOnlineServices: Bool
  /// Newest first, as `GamePersistenceStore.allGames()` returns them.
  private(set) var savedGames: [SavedGame] = []
  /// The games file exists but cannot be read. The store leaves it untouched, so no game is
  /// saved until it reads again.
  private(set) var savedGamesUnreadable = false

  @ObservationIgnored
  let feedback: any FeedbackSink
  @ObservationIgnored
  private let audio: AudioFeedback?
  @ObservationIgnored
  private let haptics: HapticFeedback?
  @ObservationIgnored
  private var controllerInput: ControllerInput?
  /// Where controller intents go; the screen that shows a board sets it and clears it.
  @ObservationIgnored
  private var controllerTarget: ((BoardInput) -> Void)?

  /// Where the model keeps its data, and whether it makes sound.
  public struct Storage {
    public var defaults: UserDefaults
    var gamesFileURL: URL
    var playsFeedback: Bool
    /// Whether the app signs in to Game Center and shows the welcome sheet.
    var usesOnlineServices: Bool

    public init(
      defaults: UserDefaults,
      gamesFileURL: URL,
      playsFeedback: Bool,
      usesOnlineServices: Bool = true
    ) {
      self.defaults = defaults
      self.gamesFileURL = gamesFileURL
      self.playsFeedback = playsFeedback
      self.usesOnlineServices = usesOnlineServices
    }

    /// Standard defaults and Application Support. With `--uitesting`, a throwaway suite and
    /// directory per process, no sound, and no online services, so UI tests start clean.
    public static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
      if arguments.contains("--uitesting") {
        let name = "Kingside.UITests.\(ProcessInfo.processInfo.processIdentifier)"
        return Self(
          defaults: UserDefaults(suiteName: name) ?? .standard,
          gamesFileURL: FileManager.default.temporaryDirectory.appending(
            components: name,
            GamePersistenceStore.fileName
          ),
          playsFeedback: false,
          usesOnlineServices: false
        )
      }
      let url =
        (try? GamePersistenceStore.defaultFileURL())
        ?? FileManager.default.temporaryDirectory.appending(
          components: "Kingside",
          GamePersistenceStore.fileName
        )
      return Self(defaults: .standard, gamesFileURL: url, playsFeedback: true)
    }
  }

  init(
    catalog: ContentCatalog,
    localization: Localization = Localization(),
    storage: Storage,
    transport: any HTTPTransport = URLSessionTransport(),
    lichessTransport: any LichessTransport = URLSessionLichessTransport(),
    bundle: Bundle = .main
  ) {
    self.catalog = catalog
    self.localization = localization
    settings = SettingsStore(defaults: storage.defaults)
    puzzleProgress = PuzzleProgressStore(
      defaults: storage.defaults,
      rating: catalog.tuning.puzzleRating
    )
    gameStore = GamePersistenceStore(fileURL: storage.gamesFileURL)
    engine = ChessEngine()
    gameCenter = GameCenterAccount()
    usesOnlineServices = storage.usesOnlineServices
    let services = catalog.services
    let product =
      bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? localization.string("app.name")
    let version =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let userAgent = services.userAgent(product: product, version: version)
    chessCom = ChessComClient(
      configuration: ChessComConfiguration(
        baseURL: services.chessCom.baseURL,
        userAgent: userAgent
      ),
      transport: transport
    )
    let lichessConfiguration = LichessConfiguration(
      baseURL: services.lichess.baseURL,
      userAgent: userAgent,
      clientID: services.lichess.clientID,
      redirectURI: services.lichess.redirectURI
    )
    lichessOAuth = LichessOAuth(configuration: lichessConfiguration, transport: lichessTransport)
    // UI tests get an empty in-memory store and never call `start()`, so they make no requests.
    let tokenStore: any TokenStore =
      storage.usesOnlineServices
      ? KeychainTokenStore(service: Self.lichessKeychainService, account: "access-token")
      : InMemoryTokenStore()
    lichess = LichessAccountModel(store: tokenStore) { tokenProvider in
      LichessClient(
        configuration: lichessConfiguration,
        transport: lichessTransport,
        tokenProvider: tokenProvider
      )
    }

    if storage.playsFeedback, let pack = catalog.soundPack(id: catalog.defaults.soundPackID) {
      let audio = AudioFeedback(pack: pack, isEnabled: settings.value.soundEffects)
      let haptics = HapticFeedback(
        haptics: catalog.feedback.haptics,
        isEnabled: settings.value.haptics
      )
      self.audio = audio
      self.haptics = haptics
      feedback = FeedbackRouter(audio: audio, haptics: haptics, tuning: catalog.feedback)
    } else {
      audio = nil
      haptics = nil
      feedback = NullFeedbackSink()
    }
    observeSettings()
  }

  /// The app's model. The bundled catalogs are checked by `ChessContentTests`, so failing to
  /// load them means a broken build.
  public static func launch() -> AppModel {
    do {
      return AppModel(catalog: try ContentCatalog.load(), storage: .live())
    } catch {
      fatalError("The bundled content catalogs do not load: \(error)")
    }
  }

  // MARK: - Appearance

  /// The chosen board theme. The catalog tests guarantee the default theme exists.
  public var boardTheme: BoardTheme {
    guard let theme = settings.value.boardTheme(in: catalog) else {
      fatalError("The default board theme \(catalog.defaults.boardThemeID) is missing")
    }
    return theme
  }

  /// The chosen piece set. The catalog tests guarantee the default set exists.
  public var pieceSet: PieceSet {
    guard let set = settings.value.pieceSet(in: catalog) else {
      fatalError("The default piece set \(catalog.defaults.pieceSetID) is missing")
    }
    return set
  }

  // MARK: - Account

  /// The first-launch welcome sheet is due.
  var showsWelcome: Bool { usesOnlineServices && !settings.value.hasSeenWelcome }

  private static let lichessKeychainService = "io.github.xsyetopz.Kingside.lichess"

  /// Signs in to Game Center at launch, unless the welcome sheet will offer it first. Resumes
  /// the Lichess session, if one is stored.
  func signInAtLaunch() {
    guard usesOnlineServices else { return }
    Task { await lichess.start() }
    guard !showsWelcome else { return }
    gameCenter.authenticate()
  }

  func finishWelcome() {
    settings.value.hasSeenWelcome = true
  }

  // MARK: - Games

  /// The game offered by Continue, if any.
  public var unfinishedGame: SavedGame? { savedGames.first { !$0.isFinished } }

  func reloadGames() async {
    do {
      savedGames = try await gameStore.allGames()
      savedGamesUnreadable = false
    } catch {
      savedGames = []
      savedGamesUnreadable = true
    }
  }

  func makeGameSession(_ launch: GameLaunch) -> GameSession {
    GameSession(
      launch: launch,
      engine: engine,
      catalog: catalog,
      localization: localization,
      settings: settings,
      store: gameStore,
      feedback: feedback
    ) { [weak self] in
      Task { await self?.reloadGames() }
    }
  }

  func makeOnlineGameSession(_ connection: any OnlineGameConnection) -> OnlineGameSession {
    OnlineGameSession(
      connection: connection,
      catalog: catalog,
      localization: localization,
      settings: settings,
      store: gameStore,
      feedback: feedback
    ) { [weak self] in
      Task { await self?.reloadGames() }
    }
  }

  func makePuzzleBoard() -> PuzzleBoardSession {
    PuzzleBoardSession(catalog: catalog, feedback: feedback)
  }

  // MARK: - Controllers

  /// Sends extended-gamepad input to `target` until `releaseController()`.
  /// The Siri Remote is not included: it drives SwiftUI focus, which the board view handles.
  func routeController(to target: @escaping (BoardInput) -> Void) {
    controllerTarget = target
    if controllerInput == nil {
      let input = ControllerInput(tuning: catalog.feedback.controller) { [weak self] intent in
        self?.controllerTarget?(intent)
      }
      input.start()
      controllerInput = input
    }
  }

  func releaseController() {
    controllerTarget = nil
  }

  // MARK: - Settings

  private func observeSettings() {
    withObservationTracking {
      _ = settings.value
    } onChange: { [weak self] in
      Task { @MainActor in self?.settingsChanged() }
    }
  }

  private func settingsChanged() {
    audio?.isEnabled = settings.value.soundEffects
    haptics?.isEnabled = settings.value.haptics
    observeSettings()
  }
}
