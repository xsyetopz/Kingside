import ChessComLink
import ChessContent
import ChessCore
import ChessOnline
import ChessPlay
import Foundation
import LichessLink
import Observation

/// Holds the stores, engine, feedback, and clients that `AppDependencies` builds, and makes the
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
  /// False under `--uitesting`: no Game Center or Lichess sign-in and no welcome sheet.
  let signsInAtLaunch: Bool
  /// Newest first, as `GamePersistenceStore.allGames()` returns them.
  private(set) var savedGames: [SavedGame] = []
  /// The games file exists but cannot be read. The store leaves it untouched, so no game is
  /// saved until it reads again.
  private(set) var savedGamesUnreadable = false

  @ObservationIgnored
  let feedback: any FeedbackSink
  @ObservationIgnored
  private let authenticateGameCenter: @MainActor () -> Void
  @ObservationIgnored
  private let setSoundEnabled: @MainActor (Bool) -> Void
  @ObservationIgnored
  private let setHapticsEnabled: @MainActor (Bool) -> Void
  @ObservationIgnored
  private let makeControllerInput: AppDependencies.ControllerInputFactory
  @ObservationIgnored
  private var controllerInput: (any ControllerInputSource)?
  /// Where controller intents go; the screen that shows a board sets it and clears it.
  @ObservationIgnored
  private var controllerTarget: ((BoardInput) -> Void)?

  init(dependencies: AppDependencies) {
    catalog = dependencies.catalog
    localization = dependencies.localization
    settings = dependencies.settings
    puzzleProgress = dependencies.puzzleProgress
    gameStore = dependencies.gameStore
    engine = dependencies.engine
    chessCom = dependencies.chessCom
    lichess = dependencies.lichess
    lichessOAuth = dependencies.lichessOAuth
    gameCenter = dependencies.gameCenter
    signsInAtLaunch = dependencies.signsInAtLaunch
    authenticateGameCenter = dependencies.authenticateGameCenter
    feedback = dependencies.feedback
    setSoundEnabled = dependencies.setSoundEnabled
    setHapticsEnabled = dependencies.setHapticsEnabled
    makeControllerInput = dependencies.makeControllerInput
    observeSettings()
  }

  /// The app's model. The bundled catalogs are checked by `ChessContentTests`, so failing to
  /// load them means a broken build.
  public static func launch() -> AppModel {
    do {
      let catalog = try ContentCatalog.load()
      return AppModel(dependencies: .live(catalog: catalog, localization: Localization()))
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
  var showsWelcome: Bool { signsInAtLaunch && !settings.value.hasSeenWelcome }

  /// Signs in to Game Center at launch, unless the welcome sheet will offer it first. Resumes
  /// the Lichess session, if one is stored.
  func signInAtLaunch() {
    guard signsInAtLaunch else { return }
    Task { await lichess.start() }
    guard !showsWelcome else { return }
    authenticateGameCenter()
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
      let input = makeControllerInput { [weak self] intent in self?.controllerTarget?(intent) }
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
    setSoundEnabled(settings.value.soundEffects)
    setHapticsEnabled(settings.value.haptics)
    observeSettings()
  }
}
