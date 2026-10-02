import ChessContent
import ChessFeedback
import Foundation
import HTTPSupportTests
import LichessLink
import Testing
@testable import ChessPlay
@testable import ChessUI

/// Records what the model asks of the injected seams.
@MainActor
private final class Seams {
  var gameCenterSignIns = 0
  var controllerInputs: [FakeControllerInput] = []
}

@MainActor
private final class FakeControllerInput: ControllerInputSource {
  let send: (BoardInput) -> Void
  private(set) var starts = 0

  init(send: @escaping (BoardInput) -> Void) { self.send = send }

  func start() { starts += 1 }
}

@MainActor
struct AppModelTests {
  private let suiteName = "ChessUITests.\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory.appending(
    path: "ChessUITests-\(UUID().uuidString)"
  )
  private let seams = Seams()
  /// Answers every request 401, so a started Lichess session stops after verifying its token.
  private let transport = FakeTransport { _ in (401, [:], Data()) }

  private func makeModel(signsInAtLaunch: Bool, hasSeenWelcome: Bool = false) throws -> AppModel {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let catalog = try ContentCatalog.load()
    let localization = Localization()
    var dependencies = AppDependencies(
      catalog: catalog,
      localization: localization,
      defaults: defaults,
      gamesFileURL: directory.appending(path: GamePersistenceStore.fileName),
      transport: transport,
      tokenStore: InMemoryTokenStore(token: "stored"),
      signsInAtLaunch: signsInAtLaunch
    )
    dependencies.settings.value.hasSeenWelcome = hasSeenWelcome
    let seams = seams
    dependencies.authenticateGameCenter = { seams.gameCenterSignIns += 1 }
    dependencies.makeControllerInput = { send in
      let input = FakeControllerInput(send: send)
      seams.controllerInputs.append(input)
      return input
    }
    return AppModel(dependencies: dependencies)
  }

  private func uiTestingDependencies() throws -> AppDependencies {
    AppDependencies.live(
      catalog: try ContentCatalog.load(),
      localization: Localization(),
      arguments: ["Kingside", "--uitesting"]
    )
  }

  /// Yields until `condition` holds; the test's time limit cancels it.
  private func wait(until condition: () async -> Bool) async throws {
    while !(await condition()) {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  @Test
  func uiTestingArgumentUsesThrowawayStorageAndNoFeedback() async throws {
    let dependencies = try uiTestingDependencies()
    defer {
      UserDefaults.standard.removePersistentDomain(
        forName: "Kingside.UITests.\(ProcessInfo.processInfo.processIdentifier)"
      )
    }
    let standardSettings = UserDefaults.standard.data(forKey: SettingsStore.defaultsKey)
    dependencies.settings.value.hasSeenWelcome.toggle()
    #expect(UserDefaults.standard.data(forKey: SettingsStore.defaultsKey) == standardSettings)
    let gamesFile = await dependencies.gameStore.fileURL
    #expect(gamesFile.path().hasPrefix(FileManager.default.temporaryDirectory.path()))
    #expect(dependencies.feedback is NullFeedbackSink)
  }

  @Test
  func appearanceFollowsSettingsAndFallsBackToDefaults() throws {
    let model = try makeModel(signsInAtLaunch: false)
    #expect(model.boardTheme.id == model.catalog.defaults.boardThemeID)
    #expect(model.pieceSet.id == model.catalog.defaults.pieceSetID)

    let other = try #require(
      model.catalog.boardThemes.first { $0.id != model.catalog.defaults.boardThemeID }
    )
    model.settings.value.boardTheme = other.id
    #expect(model.boardTheme == other)

    model.settings.value.boardTheme = "no-such-theme"
    #expect(model.boardTheme.id == model.catalog.defaults.boardThemeID)
  }

  @Test
  func freshStoreHasNoGameToContinue() async throws {
    let model = try makeModel(signsInAtLaunch: false)
    await model.reloadGames()
    #expect(model.savedGames.isEmpty)
    #expect(model.unfinishedGame == nil)
  }

  @Test
  func unreadableGamesFileIsReportedNotShownAsEmpty() async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: GamePersistenceStore.fileName)
    try Data("not json".utf8).write(to: fileURL)
    let model = try makeModel(signsInAtLaunch: false)
    await model.reloadGames()
    #expect(model.savedGamesUnreadable)
    #expect(model.savedGames.isEmpty)
  }

  @Test
  func userAgentNamesTheContact() throws {
    let catalog = try ContentCatalog.load()
    let agent = catalog.services.userAgent(product: "Kingside", version: "1.0")
    #expect(agent.contains(catalog.services.contact))
  }

  @Test
  func uiTestingArgumentTurnsLaunchSignInOffAndKeepsTheTokenInMemory() throws {
    let dependencies = try uiTestingDependencies()
    #expect(!dependencies.signsInAtLaunch)
    #expect(dependencies.lichessTokenStore is InMemoryTokenStore)
  }

  @Test
  func welcomeShowsUntilFinished() throws {
    let model = try makeModel(signsInAtLaunch: true)
    #expect(model.showsWelcome)
    model.finishWelcome()
    #expect(!model.showsWelcome)
  }

  @Test
  func welcomeNeverShowsWithoutLaunchSignIn() throws {
    let model = try makeModel(signsInAtLaunch: false)
    #expect(!model.showsWelcome)
  }

  @Test(.timeLimit(.minutes(1)))
  func launchSignInAfterTheWelcomeAsksGameCenterAndStartsLichess() async throws {
    let model = try makeModel(signsInAtLaunch: true, hasSeenWelcome: true)
    model.signInAtLaunch()
    #expect(seams.gameCenterSignIns == 1)
    try await transport.waitForRequest("GET /api/account")
  }

  @Test(.timeLimit(.minutes(1)))
  func launchSignInBeforeTheWelcomeStartsLichessButLeavesGameCenterToTheSheet() async throws {
    let model = try makeModel(signsInAtLaunch: true)
    model.signInAtLaunch()
    try await transport.waitForRequest("GET /api/account")
    #expect(seams.gameCenterSignIns == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func launchSignInIsSkippedWithoutLaunchSignIn() async throws {
    let model = try makeModel(signsInAtLaunch: false, hasSeenWelcome: true)
    model.signInAtLaunch()
    // A Lichess start would be queued on the main actor ahead of this task, and would mark the
    // account as signing in before its first request.
    await Task { @MainActor in }.value
    #expect(model.lichess.phase == .signedOut)
    #expect(await transport.paths.isEmpty)
    #expect(seams.gameCenterSignIns == 0)
  }

  @Test
  func liveArgumentsSignInAtLaunchKeepTheTokenInTheKeychainAndPlayFeedback() throws {
    let dependencies = AppDependencies.live(
      catalog: try ContentCatalog.load(),
      localization: Localization(),
      arguments: ["Kingside"]
    )
    #expect(dependencies.signsInAtLaunch)
    #expect(dependencies.lichessTokenStore is KeychainTokenStore)
    #expect(dependencies.feedback is FeedbackRouter)
  }

  @Test(.timeLimit(.minutes(1)))
  func soundAndHapticsSettingsSwitchTheAudioAndHaptics() async throws {
    let catalog = try ContentCatalog.load()
    let pack = try #require(catalog.soundPack(id: catalog.defaults.soundPackID))
    let audio = AudioFeedback(pack: pack)
    let haptics = HapticFeedback(haptics: catalog.feedback.haptics)
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    var dependencies = AppDependencies(
      catalog: catalog,
      localization: Localization(),
      defaults: defaults,
      gamesFileURL: directory.appending(path: GamePersistenceStore.fileName),
      transport: transport,
      tokenStore: InMemoryTokenStore(),
      signsInAtLaunch: false
    )
    dependencies.play(audio: audio, haptics: haptics)
    let model = AppModel(dependencies: dependencies)
    model.settings.value.soundEffects = false
    try await wait { !audio.isEnabled }
    #expect(haptics.isEnabled)
    model.settings.value.haptics = false
    try await wait { !haptics.isEnabled }
    model.settings.value.soundEffects = true
    try await wait { audio.isEnabled }
    #expect(!haptics.isEnabled)
  }

  @Test
  func controllerStartsOnceAndSendsToTheLatestTarget() throws {
    let model = try makeModel(signsInAtLaunch: false)
    var first: [BoardInput] = []
    var second: [BoardInput] = []
    model.routeController { first.append($0) }
    model.routeController { second.append($0) }
    #expect(seams.controllerInputs.count == 1)
    let input = try #require(seams.controllerInputs.first)
    #expect(input.starts == 1)

    input.send(.selectFocused)
    #expect(first.isEmpty)
    #expect(second == [.selectFocused])

    model.releaseController()
    input.send(.selectFocused)
    #expect(second == [.selectFocused])
  }

  @Test
  func everyReviewSharesOneAnalysisCache() throws {
    let model = try makeModel(signsInAtLaunch: false)
    let first = model.reviewAnalyses
    #expect(model.reviewAnalyses === first)
  }
}
