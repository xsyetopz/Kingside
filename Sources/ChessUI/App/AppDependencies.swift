import ChessComLink
import ChessContent
import ChessCore
import ChessFeedback
import ChessOnline
import ChessPlay
import Foundation
import HTTPSupport
import LichessLink

/// What `AppModel` starts once a board screen wants controller input.
@MainActor
protocol ControllerInputSource: AnyObject {
  func start()
}

extension ControllerInput: ControllerInputSource {}

/// Every collaborator `AppModel` uses, built once. `live` wires the app; tests build one from
/// their own defaults, games file, and transport, and replace the seams they observe.
@MainActor
struct AppDependencies {
  typealias ControllerInputFactory =
    @MainActor (_ send: @escaping (BoardInput) -> Void) -> any ControllerInputSource

  let catalog: ContentCatalog
  let localization: Localization
  let settings: SettingsStore
  let puzzleProgress: PuzzleProgressStore
  let gameStore: GamePersistenceStore
  let engine: ChessEngine
  let chessCom: ChessComClient
  let lichess: LichessAccountModel
  /// The OAuth calls of the Lichess browser sign-in.
  let lichessOAuth: LichessOAuth
  /// Where `lichess` keeps its token.
  let lichessTokenStore: any TokenStore
  let gameCenter: GameCenterAccount
  /// Whether launch signs in to Game Center and Lichess and offers the welcome sheet. False
  /// under `--uitesting`, so UI tests make no requests and see no sheet.
  var signsInAtLaunch: Bool
  /// The launch sign-in to Game Center.
  var authenticateGameCenter: @MainActor () -> Void
  var feedback: any FeedbackSink = NullFeedbackSink()
  /// Turn the sound effects and the haptics on or off as the settings change.
  var setSoundEnabled: @MainActor (Bool) -> Void = { _ in }
  var setHapticsEnabled: @MainActor (Bool) -> Void = { _ in }
  /// Builds the controller input that sends intents to `send`; `AppModel` starts it.
  var makeControllerInput: ControllerInputFactory

  private static let lichessKeychainService = "io.github.xsyetopz.Kingside.lichess"

  /// Silent dependencies on `defaults` and `gamesFileURL` that reach the network through
  /// `transport`.
  init(
    catalog: ContentCatalog,
    localization: Localization,
    defaults: UserDefaults,
    gamesFileURL: URL,
    transport: any HTTPStreamingTransport,
    tokenStore: any TokenStore,
    signsInAtLaunch: Bool,
    bundle: Bundle = .main
  ) {
    self.catalog = catalog
    self.localization = localization
    settings = SettingsStore(defaults: defaults)
    puzzleProgress = PuzzleProgressStore(defaults: defaults, rating: catalog.tuning.puzzleRating)
    gameStore = GamePersistenceStore(fileURL: gamesFileURL)
    engine = ChessEngine()
    let services = catalog.services
    let userAgent = Self.userAgent(services, localization: localization, bundle: bundle)
    let chessComConfiguration = ChessComConfiguration(
      baseURL: services.chessCom.baseURL,
      userAgent: userAgent
    )
    chessCom = ChessComClient(configuration: chessComConfiguration, transport: transport)
    let lichessConfiguration = LichessConfiguration(
      baseURL: services.lichess.baseURL,
      userAgent: userAgent,
      clientID: services.lichess.clientID,
      redirectURI: services.lichess.redirectURI
    )
    lichessOAuth = LichessOAuth(configuration: lichessConfiguration, transport: transport)
    lichessTokenStore = tokenStore
    lichess = LichessAccountModel(store: tokenStore) { tokenProvider in
      LichessClient(
        configuration: lichessConfiguration,
        transport: transport,
        tokenProvider: tokenProvider
      )
    }
    let gameCenter = GameCenterAccount()
    self.gameCenter = gameCenter
    self.signsInAtLaunch = signsInAtLaunch
    authenticateGameCenter = { gameCenter.authenticate() }
    let tuning = catalog.feedback.controller
    makeControllerInput = { send in ControllerInput(tuning: tuning, send: send) }
  }

  /// Standard defaults, Application Support, the Keychain, and sound. With `--uitesting`, a
  /// throwaway suite and directory per process, an in-memory token store, no sound, and no
  /// launch sign-in, so UI tests start clean.
  static func live(
    catalog: ContentCatalog,
    localization: Localization,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    bundle: Bundle = .main
  ) -> Self {
    if arguments.contains("--uitesting") {
      let name = "Kingside.UITests.\(ProcessInfo.processInfo.processIdentifier)"
      return Self(
        catalog: catalog,
        localization: localization,
        defaults: UserDefaults(suiteName: name) ?? .standard,
        gamesFileURL: FileManager.default.temporaryDirectory.appending(
          components: name,
          GamePersistenceStore.fileName
        ),
        transport: URLSessionTransport(),
        tokenStore: InMemoryTokenStore(),
        signsInAtLaunch: false,
        bundle: bundle
      )
    }
    let url =
      (try? GamePersistenceStore.defaultFileURL())
      ?? FileManager.default.temporaryDirectory.appending(
        components: "Kingside",
        GamePersistenceStore.fileName
      )
    var dependencies = Self(
      catalog: catalog,
      localization: localization,
      defaults: .standard,
      gamesFileURL: url,
      transport: URLSessionTransport(),
      tokenStore: KeychainTokenStore(service: lichessKeychainService, account: "access-token"),
      signsInAtLaunch: true,
      bundle: bundle
    )
    if let pack = catalog.soundPack(id: catalog.defaults.soundPackID) {
      let settings = dependencies.settings.value
      dependencies.play(
        audio: AudioFeedback(pack: pack, isEnabled: settings.soundEffects),
        haptics: HapticFeedback(haptics: catalog.feedback.haptics, isEnabled: settings.haptics)
      )
    }
    return dependencies
  }

  /// Plays every session event on `audio` and `haptics`, and lets the settings switch them.
  mutating func play(audio: AudioFeedback, haptics: HapticFeedback) {
    feedback = FeedbackRouter(audio: audio, haptics: haptics, tuning: catalog.feedback)
    setSoundEnabled = { audio.isEnabled = $0 }
    setHapticsEnabled = { haptics.isEnabled = $0 }
  }

  private static func userAgent(
    _ services: ServiceEndpoints,
    localization: Localization,
    bundle: Bundle
  ) -> String {
    let product =
      bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? localization.string("app.name")
    let version =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    return services.userAgent(product: product, version: version)
  }
}
