import ChessContent
import ChessPlay
import SwiftUI

/// A game against a bot or a friend. The session lives as long as the screen.
struct GameScreen: View {
    let launch: GameLaunch
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: GameSession?

    var body: some View {
        ZStack {
            if let session {
                GameView(session: session, leave: { dismiss() })
            }
        }
        .onAppear {
            if session == nil { session = model.makeGameSession(launch) }
            session?.activate()
        }
        .onDisappear { session?.deactivate() }
    }
}

/// The board with the player bars, and the moves, status, and actions: the panel sits right of
/// the board on wide screens and the moves go under it on narrow ones.
private struct GameView: View {
    let session: GameSession
    /// Leaves the screen, for New Game.
    let leave: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var confirmsResign = false
    @State private var showsResult = false

    var body: some View {
        let style = model.catalog.interface
        GeometryReader { proxy in
            if GameLayout.isWide(proxy.size, style: style.game) {
                wideLayout(style, size: proxy.size)
            } else {
                narrowLayout(style)
            }
        }
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
        session.pendingDrawOffer.map { localization.string("game.drawOffer.title", session.player($0).name) } ?? ""
    }

    /// As on Chess.com: the players above and below the board, the panel beside it. The board
    /// gets the height the two player bars leave.
    private func wideLayout(_ style: InterfaceStyle, size: CGSize) -> some View {
        let panelWidth = style.game.panelWidth * style.platformScale
        let barHeight = style.game.avatarSize * style.platformScale
        let side = max(0, min(size.width - panelWidth - style.sectionGap, size.height - 2 * (barHeight + style.gap / 2)))
        return HStack(alignment: .top, spacing: style.sectionGap) {
            VStack(spacing: style.gap / 2) {
                PlayerBar(slot: session.topPlayer, session: session)
                board.frame(width: side, height: side)
                PlayerBar(slot: session.bottomPlayer, session: session)
            }
            .frame(width: side)
            VStack(spacing: style.gap) {
                GameStatus(session: session)
                MoveList(rows: session.moveRows, axis: .vertical)
                    .frame(maxHeight: .infinity)
                    .surface(style)
                #if os(tvOS)
                GameActions(session: session, newGame: leave, confirmResign: { confirmsResign = true }, inGrid: true)
                    .buttonStyle(.bordered)
                #endif
            }
            .frame(width: panelWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func narrowLayout(_ style: InterfaceStyle) -> some View {
        VStack(spacing: style.gap) {
            PlayerBar(slot: session.topPlayer, session: session)
            board.frame(maxWidth: .infinity, maxHeight: .infinity)
            PlayerBar(slot: session.bottomPlayer, session: session)
            GameStatus(session: session)
            MoveList(rows: session.moveRows, axis: .horizontal)
        }
    }
}
