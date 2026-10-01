import ChessBoardScene
import ChessContent
import ChessPlay
import SpriteKit
import SwiftUI
// `SpriteView` lives in this cross-import overlay; the open-source toolchain does not load it
// from `import SpriteKit` plus `import SwiftUI` alone.
import _SpriteKit_SwiftUI

/// Shows a `BoardScene` and turns every input source into `BoardInput`s.
///
/// Touches and the mouse reach the scene directly. The Siri Remote drives SwiftUI focus
/// commands, keys go through `onKeyPress`, and extended gamepads go through `AppModel`.
struct BoardSceneView: View {
  let snapshot: BoardSnapshot
  /// Whether Back or Escape has something to cancel; otherwise they leave the screen.
  let canCancel: Bool
  let send: (BoardInput) -> Void

  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.displayScale)
  private var displayScale
  @State
  private var host: SceneHost?
  /// On for key and controller input, off again after a touch or click.
  @State
  private var usesDirectionalInput = false
  @FocusState
  private var isFocused: Bool

  var body: some View {
    let frame = model.catalog.interface.board
    let shape = RoundedRectangle(cornerRadius: frame.cornerRadius, style: .continuous)
    ZStack {
      if let host {
        SpriteView(scene: host.scene, options: [.allowsTransparency])
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(shape)
    .shadow(
      color: .black.opacity(frame.shadowOpacity),
      radius: frame.shadowRadius,
      y: frame.shadowYOffset
    )
    .modifier(
      BoardInputModifier(
        canCancel: canCancel,
        isFocused: $isFocused,
        snapshot: snapshot,
        label: host.map { $0.scene.accessibilityLabel(for: snapshot.focusedSquare, in: snapshot) }
          ?? ""
      ) { intent in
        usesDirectionalInput = true
        send(intent)
      }
    )
    .accessibilityIdentifier("board")
    .onAppear(perform: makeSceneIfNeeded)
    .onAppear {
      isFocused = true
      model.routeController { intent in
        usesDirectionalInput = true
        send(intent)
      }
    }
    .onDisappear { model.releaseController() }
    .onChange(of: snapshot) { _, new in
      host?.scene.apply(new, animated: model.settings.value.moveAnimation)
    }
    .onChange(of: model.boardTheme) { _, theme in host?.scene.setTheme(theme) }
    .onChange(of: model.pieceSet) { _, set in host?.scene.setPieceSet(set) }
    .onChange(of: displayScale) { _, scale in host?.scene.displayScale = scale }
    .onChange(of: usesDirectionalInput) { _, uses in
      host?.scene.showsFocusRing = Self.alwaysShowsFocus || uses
    }
  }

  /// Pointer and accessibility intents from the scene end directional mode.
  private func routeFromScene(_ intent: BoardInput) {
    switch intent {
    case .focus, .select: usesDirectionalInput = false
    default: break
    }
    send(intent)
  }

  private func makeSceneIfNeeded() {
    guard host == nil else { return }
    let host = SceneHost()
    let scene = BoardScene(
      size: CGSize(width: 512, height: 512),
      theme: model.boardTheme,
      pieceSet: model.pieceSet,
      style: model.catalog.boardStyle,
      localization: localization,
      displayScale: displayScale
    ) { [weak host] intent in host?.send(intent) }
    scene.showsFocusRing = Self.alwaysShowsFocus
    scene.apply(snapshot, animated: false)
    host.scene = scene
    host.send = routeFromScene
    self.host = host
  }

  #if os(tvOS)
    private static let alwaysShowsFocus = true
  #else
    private static let alwaysShowsFocus = false
  #endif
}

/// Owns the scene across view updates, and the closure its intents go to.
@MainActor
private final class SceneHost {
  var scene: BoardScene!
  var send: (BoardInput) -> Void = { _ in }
}

private struct BoardInputModifier: ViewModifier {
  let canCancel: Bool
  var isFocused: FocusState<Bool>.Binding
  let snapshot: BoardSnapshot
  /// The board's VoiceOver label on tvOS, where the board is a single element.
  let label: String
  let send: (BoardInput) -> Void

  #if os(tvOS)
    /// Set by a press that moved the focused square: the focus engine also moves focus to any
    /// control in that direction, and the board takes it back. Only a press at the edge leaves.
    @State
    private var holdsFocus = false
  #endif

  func body(content: Content) -> some View {
    #if os(tvOS)
      content
        .focusable()
        .focused(isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .onMoveCommand { direction in
          let move: BoardDirection
          switch direction {
          case .up: move = .up
          case .down: move = .down
          case .left: move = .left
          case .right: move = .right
          @unknown default: return
          }
          holdsFocus = !isAtEdge(move)
          send(.moveFocus(move))
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
          if !focused && holdsFocus { isFocused.wrappedValue = true }
          holdsFocus = false
        }
        .onTapGesture { send(.selectFocused) }
        // Without a selection, Back is left to navigation.
        .onExitCommand(perform: canCancel ? { send(.cancel) } : nil)
    #else
      content
        // A container, so the square elements stay reachable and the board has an identifier.
        .accessibilityElement(children: .contain)
        .focusable()
        .focused(isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: Self.handledKeys, action: handleKey)
    #endif
  }

  #if !os(tvOS)
    private static let handledKeys: Set<KeyEquivalent> = [
      .upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape,
    ]

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
      switch press.key {
      case .upArrow: send(.moveFocus(.up))
      case .downArrow: send(.moveFocus(.down))
      case .leftArrow: send(.moveFocus(.left))
      case .rightArrow: send(.moveFocus(.right))
      case .escape:
        guard canCancel else { return .ignored }
        send(.cancel)
      default: send(.selectFocused)
      }
      return .handled
    }
  #endif

  #if os(tvOS)
    /// Whether the focused square is on the board's side toward `direction`, as seen on screen.
    private func isAtEdge(_ direction: BoardDirection) -> Bool {
      let square = snapshot.focusedSquare
      let flipped = snapshot.orientation == .black
      switch direction {
      case .left: return square.file == (flipped ? 7 : 0)
      case .right: return square.file == (flipped ? 0 : 7)
      case .up: return square.rank == (flipped ? 0 : 7)
      case .down: return square.rank == (flipped ? 7 : 0)
      }
    }
  #endif
}
