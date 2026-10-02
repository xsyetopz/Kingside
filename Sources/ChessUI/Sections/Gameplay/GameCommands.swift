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

  /// The Game menu in the menu bar, so the toolbar's game actions are also menu commands, with New
  /// Game in File's New place. The menus always list the same items and dim the ones that do not
  /// apply.
  struct GameCommands: Commands {
    let localization: Localization

    var body: some Commands {
      // Replacing File > New Window, not removing it: an empty group also drops Close.
      CommandGroup(replacing: .newItem) {
        NewGameItem().environment(\.localization, localization)
      }
      CommandMenu(localization("game.title")) {
        GameMenuItems().environment(\.localization, localization)
      }
    }
  }

  /// The Game menu's commands with their titles, symbols and keyboard shortcuts.
  enum GameMenuCommand: CaseIterable {
    case hint, takeback, offerDraw, resign, flipBoard, rematch, newGame

    var titleKey: String {
      switch self {
      case .hint: "game.action.hint"
      case .takeback: "game.action.takeback"
      case .offerDraw: "game.action.offerDraw"
      case .resign: "game.action.resign"
      case .flipBoard: "game.action.flipBoard"
      case .rematch: "game.action.rematch"
      case .newGame: "game.action.newGame"
      }
    }

    var systemImage: String {
      switch self {
      case .hint: "lightbulb"
      case .takeback: "arrow.uturn.backward"
      case .offerDraw: "equal.circle"
      case .resign: "flag"
      case .flipBoard: "arrow.up.arrow.down"
      case .rematch: "arrow.counterclockwise"
      case .newGame: "plus"
      }
    }

    /// ⌘N is the standard New. The rest avoid the standard and system shortcuts: ⌘H hides the
    /// app, ⌘F is Find, and ⌘Z stays with Edit > Undo, which text fields such as chat rely on.
    var shortcut: GameMenuShortcut {
      switch self {
      case .hint: GameMenuShortcut(key: "h", shift: true)
      case .takeback: GameMenuShortcut(key: "z", option: true)
      case .offerDraw: GameMenuShortcut(key: "d", shift: true)
      case .resign: GameMenuShortcut(key: "r", shift: true)
      case .flipBoard: GameMenuShortcut(key: "f", shift: true)
      case .rematch: GameMenuShortcut(key: "n", shift: true)
      case .newGame: GameMenuShortcut(key: "n")
      }
    }
  }

  /// A Command-key shortcut, as plain values because the tests cannot import SwiftUI.
  struct GameMenuShortcut: Hashable {
    let key: Character
    var shift = false
    var option = false

    var keyboardShortcut: KeyboardShortcut {
      var modifiers: EventModifiers = .command
      if shift { modifiers.insert(.shift) }
      if option { modifiers.insert(.option) }
      return KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }
  }

  /// Views, not a `Commands` body, so the items follow the session's observed state.
  private struct GameMenuItems: View {
    @FocusedValue(\.gameMenuTarget)
    private var target

    var body: some View {
      let session = target?.session
      if target?.showsHint ?? true {
        GameMenuButton(.hint, enabled: target?.canHint ?? false) { session?.apply(.requestHint) }
      }
      if target?.showsTakeback ?? true {
        GameMenuButton(.takeback, enabled: target?.canTakeback ?? false) {
          session?.apply(.takeback)
        }
      }
      GameMenuButton(.offerDraw, enabled: target?.canOfferDraw ?? false) {
        session?.apply(.offerDraw)
      }
      GameMenuButton(.resign, enabled: target?.canResign ?? false) { target?.confirmResign() }
      Divider()
      GameMenuButton(.flipBoard, enabled: target != nil) { target?.flip() }
      if target?.showsRematch ?? true {
        Divider()
        GameMenuButton(.rematch, enabled: target?.canStartAgain ?? false) {
          session?.apply(.rematch)
        }
      }
    }
  }

  private struct NewGameItem: View {
    @FocusedValue(\.gameMenuTarget)
    private var target

    var body: some View {
      GameMenuButton(.newGame, enabled: target?.canStartAgain ?? false) { target?.newGame() }
    }
  }

  private struct GameMenuButton: View {
    let command: GameMenuCommand
    let enabled: Bool
    let action: () -> Void
    @Environment(\.localization)
    private var localization

    init(_ command: GameMenuCommand, enabled: Bool, action: @escaping () -> Void) {
      self.command = command
      self.enabled = enabled
      self.action = action
    }

    var body: some View {
      Button(localization(command.titleKey), systemImage: command.systemImage, action: action)
        .keyboardShortcut(command.shortcut.keyboardShortcut)
        .disabled(!enabled)
    }
  }
#endif
