import ChessContent
import ChessPlay
import SwiftUI

/// The board with the player bars, and the moves, status, and actions, for a local and an online
/// game: the panel sits right of the board on wide screens and the moves go under it on narrow ones.
struct GameBoardLayout<Game: PlayableGame, Board: View, Extra: View>: View {
    let session: Game
    let topPlayer: PlayerSlot
    let bottomPlayer: PlayerSlot
    let moveRows: [MoveRow]
    /// Leaves the screen, for New Game.
    let leave: () -> Void
    let confirmResign: () -> Void
    @ViewBuilder let board: Board
    /// Controls that only this kind of game has, shown under the status.
    @ViewBuilder let extra: Extra

    @Environment(AppModel.self) private var model

    var body: some View {
        let style = model.catalog.interface
        GeometryReader { proxy in
            if GameLayout.isWide(proxy.size, style: style.game) {
                wideLayout(style, size: proxy.size).environment(\.isWideGameLayout, true)
            } else {
                narrowLayout(style)
            }
        }
    }

    /// As on Chess.com: the players above and below the board, the panel beside it. The board
    /// gets the height the two player bars leave. On a short screen the bars go to the top and
    /// bottom of the panel instead, and the board gets the full height.
    private func wideLayout(_ style: InterfaceStyle, size: CGSize) -> some View {
        let panelWidth = style.game.panelWidth * style.platformScale
        let barsInPanel = GameLayout.barsInPanel(size, style: style.game)
        let bars = barsInPanel ? 0 : 2 * (style.game.avatarSize * style.platformScale + style.gap / 2)
        let side = max(0, min(size.width - panelWidth - style.sectionGap, size.height - bars))
        return HStack(alignment: .top, spacing: style.sectionGap) {
            VStack(spacing: style.gap / 2) {
                if !barsInPanel { PlayerBar(slot: topPlayer, session: session) }
                board.frame(width: side, height: side)
                if !barsInPanel { PlayerBar(slot: bottomPlayer, session: session) }
            }
            .frame(width: side)
            .frame(maxHeight: .infinity, alignment: barsInPanel ? .center : .top)
            VStack(spacing: style.gap) {
                if barsInPanel { PlayerBar(slot: topPlayer, session: session) }
                GameStatus(session: session)
                extra
                MoveList(rows: moveRows, axis: .vertical)
                    .frame(maxHeight: .infinity)
                    .surface(style)
                #if os(tvOS)
                GameActions(session: session, newGame: leave, confirmResign: confirmResign, inGrid: true)
                    .buttonStyle(.bordered)
                #endif
                if barsInPanel { PlayerBar(slot: bottomPlayer, session: session) }
            }
            .frame(width: panelWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func narrowLayout(_ style: InterfaceStyle) -> some View {
        VStack(spacing: style.gap) {
            PlayerBar(slot: topPlayer, session: session)
            board.frame(maxWidth: .infinity, maxHeight: .infinity)
            PlayerBar(slot: bottomPlayer, session: session)
            GameStatus(session: session)
            extra
            MoveList(rows: moveRows, axis: .horizontal)
        }
    }
}
