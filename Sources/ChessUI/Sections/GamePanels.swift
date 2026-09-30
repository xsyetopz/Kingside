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

/// The moves, scrolled to the latest: a score sheet of numbered rows with White's and Black's
/// moves in columns and the latest move marked, or one line on narrow screens.
struct MoveList: View {
  let rows: [MoveRow]
  let axis: Axis.Set
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  #if os(tvOS)
    @FocusState
    private var isFocused: Bool
  #endif

  var body: some View {
    let style = model.catalog.interface
    if rows.isEmpty {
      Text(localization("game.moves.empty"))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: axis == .vertical ? .infinity : nil)
        .padding(style.gap)
    } else {
      ScrollViewReader { proxy in
        ScrollView(axis) {
          if axis == .horizontal {
            LazyHStack(spacing: style.gap) {
              ForEach(rows) { row in
                Text(rowLabel(row)).monospacedDigit().id(row.id)
              }
            }
          } else {
            sheet(style)
          }
        }
        // One line is only as tall as its moves; a horizontal scroll view would otherwise take
        // all free height and shrink the board above it.
        .fixedSize(horizontal: false, vertical: axis == .horizontal)
        #if os(tvOS)
          // Focusable so the remote can scroll it; a scroll view draws no focus effect.
          .focusable()
          .focused($isFocused)
          .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(.tint, lineWidth: 2 * style.platformScale)
            .opacity(isFocused ? 1 : 0)
          }
        #endif
        .onChange(of: rows.last?.id) { _, id in
          if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
        }
      }
    }
  }

  private func sheet(_ style: InterfaceStyle) -> some View {
    let latest = rows.last
    return LazyVStack(spacing: 0) {
      ForEach(rows) { row in
        HStack(spacing: style.gap) {
          // The widest number sets the column, so the moves line up.
          ZStack(alignment: .leading) {
            Text(localization.string("game.moves.number", String(rows.count))).hidden()
            Text(localization.string("game.moves.number", String(row.number)))
          }
          .foregroundStyle(.secondary)
          move(row.white, isLatest: row.id == latest?.id && row.black == nil, style: style)
          move(row.black ?? "", isLatest: row.id == latest?.id && row.black != nil, style: style)
        }
        .monospacedDigit()
        .padding(.horizontal, style.gap)
        .padding(.vertical, style.gap / 4)
        .background(
          row.number.isMultiple(of: 2) ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(row))
        .id(row.id)
      }
    }
    .padding(.vertical, style.gap / 2)
  }

  private func move(_ san: String, isLatest: Bool, style: InterfaceStyle) -> some View {
    Text(san)
      .fontWeight(isLatest ? .semibold : .regular)
      .padding(.horizontal, style.gap / 2)
      .padding(.vertical, style.gap / 8)
      .background(
        isLatest ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: style.cornerRadius / 3, style: .continuous)
      )
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func rowLabel(_ row: MoveRow) -> String {
    localization.string("game.moves.row", String(row.number), row.white, row.black ?? "")
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
