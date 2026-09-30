import ChessContent
import SwiftUI

/// The app's root: a tab view on iOS and tvOS, a sidebar on macOS.
struct RootView: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.scenePhase)
  private var scenePhase
  @State
  private var selection: AppSection = .play
  /// The Play stack's pages, here so a started game can be pushed from any screen.
  @State
  private var playPath: [AppRoute] = []

  var body: some View {
    content
      .task {
        model.signInAtLaunch()
        await model.reloadGames()
      }
      .onChange(of: model.lichess.startedGameID) { _, id in showStartedGame(id) }
      // Events only report changes, so reload the games a background period may have hidden.
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await model.lichess.refresh() } }
      }
      .sheet(
        isPresented: Binding(get: { model.showsWelcome }, set: { if !$0 { model.finishWelcome() } })
      ) {
        WelcomeSheet { selection = .account }
      }
      .sheet(
        isPresented: Binding(
          get: { model.gameCenter.pendingSignInViewController != nil },
          set: { if !$0 { model.gameCenter.pendingSignInViewController = nil } }
        )
      ) {
        if let viewController = model.gameCenter.pendingSignInViewController {
          GameCenterSignInView(viewController: viewController)
        }
      }
  }

  /// Opens the game that has just started, unless it is already showing.
  private func showStartedGame(_ id: String?) {
    guard let id, case .signedIn = model.lichess.phase else { return }
    let route = AppRoute.onlineGame(id: id)
    selection = .play
    if playPath.last != route { playPath.append(route) }
  }

  #if os(macOS)
    @ViewBuilder
    private var content: some View {
      NavigationSplitView {
        List(AppSection.allCases, selection: Binding($selection)) { section in
          Label(localization(section.titleKey), systemImage: section.systemImage)
            .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
      } detail: {
        SectionStack(section: selection, playPath: $playPath)
          .id(selection)
      }
    }
  #else
    @ViewBuilder
    private var content: some View {
      TabView(selection: $selection) {
        ForEach(AppSection.allCases) { section in
          SectionStack(section: section, playPath: $playPath)
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
  /// The Play section's pages, which the root owns.
  @Binding
  var playPath: [AppRoute]
  @State
  private var ownPath: [AppRoute] = []

  private var path: Binding<[AppRoute]> { section == .play ? $playPath : $ownPath }

  var body: some View {
    NavigationStack(path: path) {
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
          case .onlineLobby:
            OnlineLobbyScreen()
          case .onlineGame(let id):
            OnlineGameScreen(id: id)
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
