import ChessContent
import ChessPlay
import SwiftUI

/// A game on Lichess. The session lives as long as the screen and reads the server's events
/// while the screen shows.
struct OnlineGameScreen: View {
    let id: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: OnlineGameSession?

    var body: some View {
        ZStack {
            if let session {
                if session.connectionError {
                    ConnectionErrorView { session.activate() }
                } else {
                    OnlineGameView(session: session, leave: { dismiss() })
                }
            }
        }
        .onAppear {
            if session == nil { session = model.makeOnlineGameSession(model.lichess.gameConnection(id: id)) }
            session?.activate()
        }
        .onDisappear { session?.deactivate() }
    }
}

/// Shown when the game's event stream ended with an error.
private struct ConnectionErrorView: View {
    let retry: () -> Void
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 16) {
            Text(localization("online.connection.error")).multilineTextAlignment(.center)
            Button(localization("common.retry"), systemImage: "arrow.clockwise", action: retry)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("online.connectionError")
    }
}

/// The shared game layout with the online controls, and the dialogs and toolbar that act on the session.
private struct OnlineGameView: View {
    @Bindable var session: OnlineGameSession
    /// Leaves the screen, for New Game.
    let leave: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var confirmsResign = false
    @State private var showsResult = false

    var body: some View {
        let style = model.catalog.interface
        GameBoardLayout(
            session: session, topPlayer: session.topPlayer, bottomPlayer: session.bottomPlayer, moveRows: session.moveRows,
            leave: leave, confirmResign: { confirmsResign = true },
            board: {
                BoardSceneView(snapshot: session.snapshot, canCancel: session.hasCancellableSelection) {
                    session.apply($0)
                }
            },
            extra: { onlineControls }
        )
        .padding(style.gap)
        .screenTitle(localization("game.title"), chrome: .board)
        #if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    GameActions(session: session, newGame: leave) { confirmsResign = true }
                } label: {
                    Label(localization("game.action.menu"), systemImage: "ellipsis.circle")
                }
            }
        }
        .focusedSceneValue(\.gameMenuTarget, GameMenuTarget(
            session: session, newGame: leave, confirmResign: { confirmsResign = true },
            flip: { session.apply(.flipBoard) }))
        #endif
        .confirmationDialog(localization("game.resign.title"), isPresented: $confirmsResign, titleVisibility: .visible) {
            Button(localization("game.action.resign"), role: .destructive) { session.apply(.resign) }
        }
        .alert(
            drawOfferTitle, isPresented: .constant(session.pendingDrawOffer != nil)
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

    private var drawOfferTitle: String {
        session.pendingDrawOffer.map { localization.string("game.drawOffer.title", session.player($0).name) } ?? ""
    }

    /// The chat; Abort while the game has fewer than two moves; Claim Victory once the opponent has been gone long enough.
    @ViewBuilder private var onlineControls: some View {
        VStack(spacing: 8) {
            OnlineChatControls(session: session)
            gameControls
        }
    }

    @ViewBuilder private var gameControls: some View {
        if session.canAbort || session.canClaimVictory {
            HStack {
                if session.canAbort {
                    Button(role: .destructive) { session.abort() } label: {
                        Label(localization("online.action.abort"), systemImage: "xmark.circle").lineLimit(1)
                    }
                }
                if session.canClaimVictory {
                    Button { session.claimVictory() } label: {
                        Label(localization("online.action.claimVictory"), systemImage: "flag.checkered").lineLimit(1)
                    }
                }
            }
            #if os(tvOS)
            .buttonStyle(.bordered)
            #endif
        }
    }
}
