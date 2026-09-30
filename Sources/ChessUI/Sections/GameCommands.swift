#if !os(tvOS)
  import ChessContent
  import ChessPlay
  import SwiftUI

  /// What the Game menu acts on: the focused game, or a puzzle, which only flips its board.
  @MainActor
  struct GameMenuTarget {
    var session: (any PlayableGame)?
    var newGame: () -> Void = {}
    var confirmResign: () -> Void = {}
    let flip: () -> Void

    /// The Hint, Takeback and Rematch items are shown unless the game cannot do them; a puzzle
    /// has no game and keeps them dimmed.
    var showsHint: Bool { session?.supportsHint ?? true }
    var showsTakeback: Bool { session?.supportsTakeback ?? true }
    var showsRematch: Bool { session?.supportsRematch ?? true }

    var canHint: Bool {
      session.map { $0.supportsHint && $0.canMove && !$0.isLoadingHint } ?? false
    }
    var canTakeback: Bool { session?.canTakeback ?? false }
    var canOfferDraw: Bool { session?.canOfferDraw ?? false }
    var canResign: Bool { session.map { !$0.isGameOver } ?? false }
    /// Rematch and New Game.
    var canStartAgain: Bool { session?.isGameOver ?? false }
  }

  extension FocusedValues {
    @Entry
    var gameMenuTarget: GameMenuTarget?
  }

  /// The Game menu in the menu bar, so the toolbar's game actions are also menu commands. It always
  /// lists the same items and dims the ones that do not apply.
  struct GameCommands: Commands {
    let localization: Localization

    var body: some Commands {
      CommandMenu(localization("game.title")) {
        GameMenuItems().environment(\.localization, localization)
      }
    }
  }

  /// A view, not a `Commands` body, so the items follow the session's observed state.
  private struct GameMenuItems: View {
    @FocusedValue(\.gameMenuTarget)
    private var target
    @Environment(\.localization)
    private var localization

    var body: some View {
      let session = target?.session
      if target?.showsHint ?? true {
        item("game.action.hint", "lightbulb", enabled: target?.canHint ?? false) {
          session?.apply(.requestHint)
        }
      }
      if target?.showsTakeback ?? true {
        item("game.action.takeback", "arrow.uturn.backward", enabled: target?.canTakeback ?? false)
        {
          session?.apply(.takeback)
        }
      }
      item("game.action.offerDraw", "equal.circle", enabled: target?.canOfferDraw ?? false) {
        session?.apply(.offerDraw)
      }
      item("game.action.resign", "flag", enabled: target?.canResign ?? false) {
        target?.confirmResign()
      }
      Divider()
      item("game.action.flipBoard", "arrow.up.arrow.down", enabled: target != nil) {
        target?.flip()
      }
      Divider()
      let canStartAgain = target?.canStartAgain ?? false
      if target?.showsRematch ?? true {
        item("game.action.rematch", "arrow.counterclockwise", enabled: canStartAgain) {
          session?.apply(.rematch)
        }
      }
      item("game.action.newGame", "plus", enabled: canStartAgain) { target?.newGame() }
    }

    private func item(
      _ key: String,
      _ systemImage: String,
      enabled: Bool,
      action: @escaping () -> Void
    ) -> some View {
      Button(localization(key), systemImage: systemImage, action: action).disabled(!enabled)
    }
  }
#endif
