import ChessContent
import ChessPlay
import SwiftUI

/// One labeled value in a puzzle screen's status card.
struct PuzzleStat: Identifiable {
  let title: String
  let value: String

  var id: String { title }
}

/// The button under the status card that moves the screen on: Next, Start Over, or End Run.
struct PuzzleAction {
  let title: String
  let systemImage: String
  var isEnabled = true
  let perform: () -> Void
}

/// The layout the puzzle screens share: the board, and a panel with the status card, the stats,
/// and the actions. The panel sits right of the board on wide screens and under it on narrow ones.
struct PuzzleScreenLayout<Header: View>: View {
  let title: String
  let board: PuzzleBoardSession
  let stats: [PuzzleStat]
  let primary: PuzzleAction
  /// Whether the panel offers Retry. Puzzle Rush moves on by itself and leaves it out.
  var offersRetry = true
  /// Content above the status card, such as the Puzzle Rush clock.
  @ViewBuilder
  let header: Header

  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    GeometryReader { proxy in
      if GameLayout.isWide(proxy.size, style: style.game) {
        HStack(spacing: style.sectionGap) {
          boardView.frame(maxWidth: .infinity, maxHeight: .infinity)
          ScrollView {
            panel(style, isWide: true)
          }
          .frame(width: style.game.panelWidth * style.platformScale)
        }
      } else {
        VStack(spacing: style.gap) {
          boardView.frame(maxWidth: .infinity, maxHeight: .infinity)
          panel(style, isWide: false)
        }
      }
    }
    .padding(style.gap)
    .screenTitle(title, chrome: .board)
    #if !os(tvOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) { flipButton.labelStyle(.iconOnly) }
      }
      .focusedSceneValue(\.gameMenuTarget, GameMenuTarget { board.apply(.flipBoard) })
    #endif
  }

  private var boardView: some View {
    let snapshot = board.snapshot
    return BoardSceneView(
      snapshot: snapshot,
      canCancel: snapshot.selectedSquare != nil || snapshot.pendingPromotion != nil
    ) {
      board.apply($0)
    }
  }

  private func panel(_ style: InterfaceStyle, isWide: Bool) -> some View {
    VStack(spacing: style.gap) {
      header
      statusCard(style)
      actionButton(primary).buttonStyle(.borderedProminent)
      if isWide {
        // Equal cells, two to a row, and a last odd one across both, as in the game panel.
        EqualColumns(spacing: style.gap) { secondaryButtons }
          .buttonStyle(.bordered)
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: style.gap) { secondaryButtons }.buttonStyle(.bordered)
          HStack(spacing: style.gap) { secondaryButtons }.buttonStyle(.bordered).labelStyle(
            .iconOnly
          )
        }
      }
    }
    .controlSize(.large)
  }

  private func statusCard(_ style: InterfaceStyle) -> some View {
    VStack(alignment: .leading, spacing: style.gap) {
      Text(localization(PuzzleLayout.statusKey(phase: board.phase, solverColor: board.solverColor)))
        .font(.headline)
      ForEach(stats) { stat in
        LabeledContent(stat.title) { Text(stat.value).monospacedDigit() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(style.gap)
    .contentPanel(style)
  }

  /// The buttons under the primary one, in order.
  private var secondaryActions: [PuzzleAction] {
    var actions = [
      PuzzleAction(
        title: localization("game.action.hint"),
        systemImage: "lightbulb",
        isEnabled: board.canHint
      ) {
        board.apply(.requestHint)
      },
      PuzzleAction(
        title: localization("puzzles.action.showSolution"),
        systemImage: "eye",
        isEnabled: board.canShowSolution
      ) {
        board.showSolution()
      },
    ]
    if offersRetry {
      actions.append(
        PuzzleAction(
          title: localization("common.retry"),
          systemImage: "arrow.counterclockwise",
          isEnabled: board.canRetry
        ) {
          board.retry()
        }
      )
    }
    #if os(tvOS)
      actions.append(
        PuzzleAction(
          title: localization("game.action.flipBoard"),
          systemImage: "arrow.up.arrow.down"
        ) {
          board.apply(.flipBoard)
        }
      )
    #endif
    return actions
  }

  private var secondaryButtons: some View {
    let actions = secondaryActions
    return ForEach(actions.indices, id: \.self) { actionButton(actions[$0]) }
  }

  #if !os(tvOS)
    private var flipButton: some View {
      Button(localization("game.action.flipBoard"), systemImage: "arrow.up.arrow.down") {
        board.apply(.flipBoard)
      }
    }
  #endif

  /// A button as wide as its space; the caller sets the button style.
  private func actionButton(
    _ title: String,
    _ systemImage: String,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage).lineLimit(1).frame(maxWidth: .infinity)
    }
    .disabled(!isEnabled)
  }

  private func actionButton(_ action: PuzzleAction) -> some View {
    actionButton(
      action.title,
      action.systemImage,
      isEnabled: action.isEnabled,
      action: action.perform
    )
  }
}

extension PuzzleScreenLayout where Header == EmptyView {
  init(title: String, board: PuzzleBoardSession, stats: [PuzzleStat], primary: PuzzleAction) {
    self.init(title: title, board: board, stats: stats, primary: primary) { EmptyView() }
  }
}
