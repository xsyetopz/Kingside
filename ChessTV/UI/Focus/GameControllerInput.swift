import Foundation
import GameController
import SwiftUI

@MainActor
final class GameControllerInput: ObservableObject {
    var moveHandler: ((MoveCommandDirection) -> Void)?
    var primaryHandler: (() -> Void)?
    var secondaryHandler: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.configureConnectedControllers() }
        })
        configureConnectedControllers()
        GCController.startWirelessControllerDiscovery()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        GCController.stopWirelessControllerDiscovery()
    }

    private func configureConnectedControllers() {
        for controller in GCController.controllers() { configure(controller) }
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.moveHandler?(.up) } } }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.moveHandler?(.down) } } }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.moveHandler?(.left) } } }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.moveHandler?(.right) } } }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard abs(x) > 0.7 || abs(y) > 0.7 else { return }
            let direction: MoveCommandDirection = abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
            Task { @MainActor in self?.moveHandler?(direction) }
        }
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.primaryHandler?() } } }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in if pressed { Task { @MainActor in self?.secondaryHandler?() } } }
    }
}
