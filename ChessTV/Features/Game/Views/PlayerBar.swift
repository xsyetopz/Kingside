import SwiftUI
import ChessCore

// Player strip drawn above and below the board:
//   avatar | bold name, muted rating, "thinking…" | captured pieces with "+N" | clock
// The clock sits at the trailing edge, so give the bar the board's width to line them up.

struct PlayerBar: View {
    let slot: PlayerSlot
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        HStack(spacing: 18) {
            PlayerAvatar(info: slot.info, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(slot.info.name)
                        .font(ChessFont.body.weight(.bold))
                        .lineLimit(1)
                    if let rating = slot.info.rating {
                        Text(verbatim: "(\(rating))")
                            .font(ChessFont.bodyRegular)
                            .foregroundStyle(ChessTheme.textMuted)
                    }
                    if isThinking { ThinkingIndicator() }
                }
                CapturedPiecesView(
                    captured: viewModel.capturedPieces[slot.color] ?? [],
                    color: slot.color.opponent,
                    advantage: viewModel.materialAdvantage[slot.color] ?? 0,
                    pieceSize: 26
                )
                .frame(height: 28, alignment: .leading)
            }
            Spacer(minLength: 0)
            PlayerClock(color: slot.color, clock: viewModel.clock)
        }
        .accessibilityElement(children: .combine)
    }

    private var isThinking: Bool { viewModel.isBotThinking && slot.info.isBot }
}

/// The bot's own avatar for bot players, initials for humans.
struct PlayerAvatar: View {
    let info: PlayerInfo
    var size: CGFloat = 64

    var body: some View {
        if let bot = info.botID.flatMap(BotRoster.bot(id:)) {
            bot.avatar(size: size)
        } else {
            AvatarView(name: info.name, size: size)
        }
    }
}

private struct PlayerClock: View {
    let color: PieceColor
    @ObservedObject var clock: GameClockModel

    var body: some View {
        ClockView(
            time: clock.isTimed ? clock.remaining(color) : .infinity,
            isActive: clock.activeColor == color,
            isLow: clock.isLow(color),
            width: 190
        )
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("thinking…")
        }
        .font(ChessFont.caption)
        .foregroundStyle(ChessTheme.textSecondary)
        .transition(.opacity)
        .accessibilityLabel("Thinking")
    }
}
