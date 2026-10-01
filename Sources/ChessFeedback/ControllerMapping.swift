import ChessContent
import ChessPlay
import Foundation

/// A controller button that the board uses.
enum ControllerButton: Equatable, Sendable {
  case a, b
}

/// Turns controller state into board input, without hardware.
///
/// The d-pad wins over the thumbstick while both point somewhere. A new direction moves the
/// cursor at once; a held one repeats after `repeatDelay`, then every `repeatInterval`.
/// Times are seconds on any monotonic clock.
struct ControllerMapping: Equatable {
  let tuning: ControllerTuning
  private var dpad: BoardDirection?
  private var stick: BoardDirection?
  private var held: BoardDirection?
  /// When the held direction repeats next; nil while nothing is held.
  private(set) var nextRepeat: TimeInterval?

  init(tuning: ControllerTuning) {
    self.tuning = tuning
  }

  /// The direction of an axis pair (y up), or nil inside the threshold.
  static func direction(x: Float, y: Float, threshold: Double) -> BoardDirection? {
    let threshold = Float(threshold)
    guard max(abs(x), abs(y)) >= threshold else { return nil }
    if abs(x) > abs(y) { return x > 0 ? .right : .left }
    return y > 0 ? .up : .down
  }

  static func input(for button: ControllerButton) -> BoardInput {
    switch button {
    case .a: .selectFocused
    case .b: .cancel
    }
  }

  mutating func dpadChanged(x: Float, y: Float, at time: TimeInterval) -> [BoardInput] {
    dpad = Self.direction(x: x, y: y, threshold: tuning.axisThreshold)
    return update(at: time)
  }

  mutating func stickChanged(x: Float, y: Float, at time: TimeInterval) -> [BoardInput] {
    stick = Self.direction(x: x, y: y, threshold: tuning.axisThreshold)
    return update(at: time)
  }

  /// Repeats of the held direction that are due at `time`.
  mutating func tick(at time: TimeInterval) -> [BoardInput] {
    guard let direction = held, var due = nextRepeat else { return [] }
    var inputs: [BoardInput] = []
    while due <= time {
      inputs.append(.moveFocus(direction))
      due += tuning.repeatInterval
    }
    nextRepeat = due
    return inputs
  }

  /// Forgets every held direction, such as when a controller disconnects.
  mutating func reset() {
    dpad = nil
    stick = nil
    held = nil
    nextRepeat = nil
  }

  private mutating func update(at time: TimeInterval) -> [BoardInput] {
    let direction = dpad ?? stick
    guard direction != held else { return tick(at: time) }
    held = direction
    guard let direction else {
      nextRepeat = nil
      return []
    }
    nextRepeat = time + tuning.repeatDelay
    return [.moveFocus(direction)]
  }
}
