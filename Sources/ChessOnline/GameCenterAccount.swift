import Foundation
import GameKit
import Observation

/// Where the Game Center sign-in stands.
public enum GameCenterState: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn(displayName: String)
    /// Game Center cannot be used on this device, for example because it is restricted; `message`
    /// is the system's description.
    case unavailable(message: String)

    /// Maps what GameKit reported to a state. `needsUserInterface` is true when GameKit handed over
    /// a sign-in screen. A cancelled sign-in leaves the player signed out; any other error means
    /// Game Center is unavailable.
    public static func resolve(
        isAuthenticated: Bool, displayName: String, needsUserInterface: Bool, error: (any Error)?
    ) -> GameCenterState {
        if isAuthenticated { return .signedIn(displayName: displayName) }
        if let error {
            let nsError = error as NSError
            if nsError.domain == GKError.errorDomain, nsError.code == GKError.Code.cancelled.rawValue {
                return .signedOut
            }
            return .unavailable(message: error.localizedDescription)
        }
        return needsUserInterface ? .signingIn : .signedOut
    }
}

/// The player's Game Center sign-in, which is the app's sign-in. GameKit-specific code is limited to
/// `authenticate()` and `openDashboard()`.
@Observable
@MainActor
public final class GameCenterAccount {
#if canImport(UIKit)
    public typealias PlatformViewController = UIViewController
#else
    public typealias PlatformViewController = NSViewController
#endif

    public private(set) var state: GameCenterState = .signedOut
    /// The sign-in screen Game Center asks the app to show; nil once it is dismissed or finished.
    public var pendingSignInViewController: PlatformViewController?

    public init() {}

    /// Starts sign-in. GameKit calls the handler again whenever the player signs in or out.
    public func authenticate() {
        state = .signingIn
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            let screen = ViewControllerBox(viewController)
            Task { @MainActor in self?.apply(screen.viewController, error: error) }
        }
    }

    /// Shows the Game Center dashboard.
    public func openDashboard() {
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    private func apply(_ viewController: PlatformViewController?, error: (any Error)?) {
        pendingSignInViewController = viewController
        let player = GKLocalPlayer.local
        state = GameCenterState.resolve(
            isAuthenticated: player.isAuthenticated, displayName: player.displayName,
            needsUserInterface: viewController != nil, error: error)
    }
}

/// GameKit calls the handler on the main queue; the box only moves its screen to the main actor.
private struct ViewControllerBox: @unchecked Sendable {
    let viewController: GameCenterAccount.PlatformViewController?

    init(_ viewController: GameCenterAccount.PlatformViewController?) {
        self.viewController = viewController
    }
}
