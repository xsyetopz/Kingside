import ChessContent
import ChessPlay
import SwiftUI

/// A game against a bot or a friend. The session lives as long as the screen.
struct GameScreen: View {
  let launch: GameLaunch
  @Environment(AppModel.self)
  private var model
  @Environment(\.dismiss)
  private var dismiss
  @State
  private var session: GameSession?

  var body: some View {
    ZStack {
      if let session {
        GameView(session: session) { dismiss() }
      }
    }
    .onAppear {
      if session == nil { session = model.makeGameSession(launch) }
      session?.activate()
    }
    .onDisappear { session?.deactivate() }
  }
}

/// The game's layout plus the dialogs and toolbar that act on the session.
private struct GameView: View {
  @Bindable
  var session: GameSession
  /// Leaves the screen, for New Game.
  let leave: () -> Void

  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @State
  private var confirmsResign = false
  @State
  private var showsResult = false

  var body: some View {
    let style = model.catalog.interface
    GameBoardLayout(
      session: session,
      topPlayer: session.topPlayer,
      bottomPlayer: session.bottomPlayer,
      moveRows: session.moveRows,
      leave: leave,
      confirmResign: { confirmsResign = true },
      board: { board },
      extra: {}
    )
    .padding(style.gap)
    .screenTitle(localization("game.title"), chrome: .board)
    #if !os(tvOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            actions
          } label: {
            Label(localization("game.action.menu"), systemImage: "ellipsis.circle")
          }
        }
      }
      .focusedSceneValue(
        \.gameMenuTarget,
        GameMenuTarget(
          session: session,
          newGame: leave,
          confirmResign: { confirmsResign = true },
          flip: { session.apply(.flipBoard) }
        )
      )
    #endif
    .confirmationDialog(
      localization("game.resign.title"),
      isPresented: $confirmsResign,
      titleVisibility: .visible
    ) {
      Button(localization("game.action.resign"), role: .destructive) { session.apply(.resign) }
    }
    .alert(
      drawOfferTitle,
      isPresented: .constant(session.pendingDrawOffer != nil)
    ) {
      Button(localization("game.drawOffer.accept")) { session.apply(.acceptDraw) }
      Button(localization("game.drawOffer.decline"), role: .cancel) { session.apply(.declineDraw) }
    }
    .alert(localization("game.saveFailed.title"), isPresented: $session.showsSaveFailure) {
    } message: {
      Text(localization("game.saveFailed.detail"))
    }
    .sheet(isPresented: $showsResult) {
      GameResultSheet(session: session, newGame: leave)
    }
    .onChange(of: session.isGameOver) { _, isOver in showsResult = isOver }
  }

  private var board: some View {
    BoardSceneView(snapshot: session.snapshot, canCancel: session.hasCancellableSelection) {
      session.apply($0)
    }
  }

  private var actions: some View {
    GameActions(session: session, newGame: leave) { confirmsResign = true }
  }

  private var drawOfferTitle: String {
    session.pendingDrawOffer.map {
      localization.string("game.drawOffer.title", session.player($0).name)
    } ?? ""
  }
}
