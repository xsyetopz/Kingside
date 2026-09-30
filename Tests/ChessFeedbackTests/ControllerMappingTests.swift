import ChessContent
import ChessPlay
import Foundation
import Testing

@testable import ChessFeedback

@Suite
struct ControllerMappingTests {
  private static let tuning = try! JSONDecoder().decode(
    ControllerTuning.self,
    from: Data(#"{"repeatDelay": 0.4, "repeatInterval": 0.1, "axisThreshold": 0.5}"#.utf8)
  )

  @Test(arguments: [
    (Float(0), Float(1), BoardDirection?.some(.up)), (0, -1, .down), (-1, 0, .left), (1, 0, .right),
    (0.9, 0.6, .right), (-0.3, -0.8, .down), (0.4, 0.4, nil), (0, 0, nil),
  ])
  func mapsAxesToDirections(x: Float, y: Float, direction: BoardDirection?) {
    #expect(ControllerMapping.direction(x: x, y: y, threshold: 0.5) == direction)
  }

  @Test
  func mapsButtons() {
    #expect(ControllerMapping.intent(for: .a) == .selectFocused)
    #expect(ControllerMapping.intent(for: .b) == .cancel)
  }

  @Test
  func repeatsAHeldDirectionAfterTheDelay() {
    var mapping = ControllerMapping(tuning: Self.tuning)
    #expect(mapping.dpadChanged(x: 0, y: 1, at: 10) == [.moveFocus(.up)])
    // Holding the same direction does not move again before the delay.
    #expect(mapping.dpadChanged(x: 0, y: 1, at: 10.2).isEmpty)
    #expect(mapping.tick(at: 10.39).isEmpty)
    #expect(mapping.tick(at: 10.4) == [.moveFocus(.up)])
    #expect(mapping.nextRepeat == 10.5)
    // A late tick catches up on every repeat that was due.
    #expect(mapping.tick(at: 10.72) == Array(repeating: .moveFocus(.up), count: 3))
    // Releasing stops the repeat.
    #expect(mapping.dpadChanged(x: 0, y: 0, at: 10.8).isEmpty)
    #expect(mapping.nextRepeat == nil)
    #expect(mapping.tick(at: 20).isEmpty)
  }

  @Test
  func aNewDirectionMovesAtOnceAndRestartsTheDelay() {
    var mapping = ControllerMapping(tuning: Self.tuning)
    _ = mapping.stickChanged(x: 1, y: 0, at: 0)
    #expect(mapping.stickChanged(x: 0, y: -1, at: 0.3) == [.moveFocus(.down)])
    #expect(mapping.nextRepeat == 0.3 + 0.4)
  }

  @Test
  func theDpadWinsOverTheThumbstick() {
    var mapping = ControllerMapping(tuning: Self.tuning)
    #expect(mapping.stickChanged(x: -1, y: 0, at: 0) == [.moveFocus(.left)])
    #expect(mapping.dpadChanged(x: 1, y: 0, at: 0.1) == [.moveFocus(.right)])
    // The stick still points left, so releasing the d-pad goes back to it.
    #expect(mapping.dpadChanged(x: 0, y: 0, at: 0.2) == [.moveFocus(.left)])
    mapping.reset()
    #expect(mapping.nextRepeat == nil)
    #expect(mapping.tick(at: 5).isEmpty)
  }
}
