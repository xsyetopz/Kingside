import ChessContent
import ChessCore
import ChessPlay
import SwiftUI

/// One player: avatar, name, rating, material lead, and the clock of a timed game.
struct PlayerBar<Game: PlayableGame>: View {
  let slot: PlayerSlot
  let session: Game

  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    let bot = slot.info.botID.flatMap { model.catalog.bots.bot(id: $0) }
    let lead = session.materialAdvantage[slot.color] ?? 0
    HStack(spacing: style.gap) {
      AvatarView(
        symbol: bot?.avatar.symbol ?? (slot.info.isBot ? nil : "person.fill"),
        name: slot.info.name
      )
      VStack(alignment: .leading) {
        Text(slot.info.name).font(.headline)
        HStack {
          if let rating = slot.info.rating { Text(localization.string("playBots.elo", rating)) }
          if lead > 0 { Text(localization.string("game.material.lead", lead)) }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if session.clock.isTimed { clock(style) }
    }
  }

  private func clock(_ style: InterfaceStyle) -> some View {
    let isActive = session.activeClockColor == slot.color
    return Text(GameLayout.clockText(session.clock.remaining(slot.color)))
      .font(.title3.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(
        session.isLowTime(slot.color) ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
      )
      .padding(.horizontal, style.gap)
      .padding(.vertical, style.gap / 2)
      .background(
        isActive ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
        in: RoundedRectangle(cornerRadius: style.cornerRadius / 2, style: .continuous)
      )
      .accessibilityLabel(localization.string("game.clock.label", slot.info.name))
  }
}

/// A round avatar: the SF Symbol, or the initial of `name` without one.
struct AvatarView: View {
  let symbol: String?
  let name: String
  /// Multiplies `avatarSize`, for cards that show the avatar as their artwork.
  var scale: Double = 1
  @Environment(AppModel.self)
  private var model

  var body: some View {
    let size =
      model.catalog.interface.game.avatarSize * model.catalog.interface.platformScale * scale
    ZStack {
      Circle().fill(.quaternary)
      // The avatar has a fixed size, so its glyph follows the size, not Dynamic Type.
      if let symbol {
        Image(systemName: symbol).font(.system(size: size * 0.45)).foregroundStyle(.tint)
      } else {
        Text(name.prefix(1)).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(
          .tint
        )
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// The turn or result line, and the bot's latest chat line.
struct GameStatus<Game: PlayableGame>: View {
  let session: Game
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    VStack(alignment: .leading, spacing: style.gap) {
      if session.isGameOver {
        VStack(alignment: .leading) {
          Text(session.resultTitle).font(.headline)
          Text(session.resultReason).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
      } else {
        Text(session.statusText).font(.headline)
      }
      if let message = session.botMessage {
        HStack(alignment: .firstTextBaseline) {
          Text(message).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Button {
            session.apply(.dismissBotMessage)
          } label: {
            Label(localization("game.botMessage.dismiss"), systemImage: "xmark.circle.fill")
              .labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(style.gap)
    .surface(style)
  }
}

/// The game actions as buttons: a flat list for a menu, or equal-width buttons in a grid.
struct GameActions<Game: PlayableGame>: View {
  let session: Game
  let newGame: () -> Void
  let confirmResign: () -> Void
  /// Lays the buttons out in two equal columns, Resign across both.
  var inGrid = false
  @Environment(\.localization)
  private var localization

  var body: some View {
    if inGrid {
      EqualColumns {
        if session.isGameOver {
          rematch
          newGameButton
        } else {
          hint
          takeback
          offerDraw
          flip
          resign
        }
      }
    } else if session.isGameOver {
      rematch
      newGameButton
    } else {
      hint
      takeback
      offerDraw
      flip
      resign
    }
  }

  @ViewBuilder
  private var rematch: some View {
    if session.supportsRematch { rematchButton }
  }

  private var rematchButton: some View {
    button("game.action.rematch", "arrow.counterclockwise") { session.apply(.rematch) }
  }

  private var newGameButton: some View {
    button("game.action.newGame", "plus", action: newGame)
  }

  @ViewBuilder
  private var hint: some View {
    if session.supportsHint {
      button("game.action.hint", "lightbulb") { session.apply(.requestHint) }
        .disabled(!session.canMove || session.isLoadingHint)
    }
  }

  @ViewBuilder
  private var takeback: some View {
    if session.supportsTakeback {
      button("game.action.takeback", "arrow.uturn.backward") { session.apply(.takeback) }
        .disabled(!session.canTakeback)
    }
  }

  private var offerDraw: some View {
    button("game.action.offerDraw", "equal.circle") { session.apply(.offerDraw) }
      .disabled(!session.canOfferDraw)
  }

  private var flip: some View {
    button("game.action.flipBoard", "arrow.up.arrow.down") { session.apply(.flipBoard) }
  }

  private var resign: some View {
    button("game.action.resign", "flag", role: .destructive, action: confirmResign)
  }

  private func button(
    _ key: String,
    _ systemImage: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Label(localization(key), systemImage: systemImage)
        .lineLimit(1)
        .frame(maxWidth: inGrid ? .infinity : nil)
    }
  }
}

/// Shown when the game ends: the result, and what to do next.
struct GameResultSheet<Game: PlayableGame>: View {
  let session: Game
  let newGame: () -> Void
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    let style = model.catalog.interface
    VStack(spacing: style.sectionGap) {
      VStack(spacing: style.gap / 2) {
        Text(session.resultTitle).font(.largeTitle.bold())
        Text(session.resultReason).font(.title3).foregroundStyle(.secondary)
      }
      VStack(spacing: style.gap) {
        if session.supportsRematch {
          Button {
            session.apply(.rematch)
          } label: {
            Text(localization("game.action.rematch")).frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }
        Button {
          dismiss()
          newGame()
        } label: {
          Text(localization("game.action.newGame")).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        Button(localization("common.close")) { dismiss() }
          .buttonStyle(.borderless)
      }
      // The column takes its widest button's width, so the two main buttons match.
      .fixedSize(horizontal: true, vertical: false)
      .controlSize(.large)
    }
    .padding(style.sectionGap)
    #if os(iOS)
      .presentationDetents([.medium])
    #endif
  }
}
