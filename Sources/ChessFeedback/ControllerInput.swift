import ChessContent
import ChessPlay
import Foundation
import GameController

/// Sends board intents from extended game controllers.
///
/// The d-pad and left thumbstick move the cursor; A selects and B cancels. `ControllerMapping`
/// holds the rules. The Siri Remote is left out on purpose: it drives the SwiftUI focus engine,
/// which the board view already turns into intents, so handling it here would double each move.
@MainActor
public final class ControllerInput {
    private let send: (BoardIntent) -> Void
    private let now: () -> TimeInterval
    private var mapping: ControllerMapping
    private var repeatTask: Task<Void, Never>?
    private let observers = NotificationObservers()
    private var isStarted = false

    public init(
        tuning: ControllerTuning,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        send: @escaping (BoardIntent) -> Void
    ) {
        self.mapping = ControllerMapping(tuning: tuning)
        self.now = now
        self.send = send
    }

    /// Observes controllers as they connect and disconnect, and configures those already connected.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        observers.add(.GCControllerDidConnect) { [weak self] _ in
            MainActor.assumeIsolated { self?.configureConnected() }
        }
        observers.add(.GCControllerDidDisconnect) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        }
        configureConnected()
    }

    private func configureConnected() {
        for controller in GCController.controllers() { configure(controller) }
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.handle { $0.dpadChanged(x: x, y: y, at: $1) } }
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.handle { $0.stickChanged(x: x, y: y, at: $1) } }
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.send(ControllerMapping.intent(for: .a)) } }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.send(ControllerMapping.intent(for: .b)) } }
        }
    }

    private func handle(_ change: (inout ControllerMapping, TimeInterval) -> [BoardIntent]) {
        change(&mapping, now()).forEach(send)
        scheduleRepeat()
    }

    private func releaseAll() {
        mapping.reset()
        scheduleRepeat()
    }

    /// Wakes at the next repeat of the held direction and sends it.
    private func scheduleRepeat() {
        repeatTask?.cancel()
        guard let due = mapping.nextRepeat else {
            repeatTask = nil
            return
        }
        let delay = max(0, due - now())
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.handle { mapping, time in mapping.tick(at: time) }
        }
    }
}
