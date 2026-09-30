import ChessOnline
import SwiftUI

/// Shows the sign-in screen Game Center hands the app.
#if canImport(UIKit)
struct GameCenterSignInView: UIViewControllerRepresentable {
    let viewController: GameCenterAccount.PlatformViewController

    func makeUIViewController(context: Context) -> GameCenterAccount.PlatformViewController { viewController }
    func updateUIViewController(_ uiViewController: GameCenterAccount.PlatformViewController, context: Context) {}
}
#else
struct GameCenterSignInView: NSViewControllerRepresentable {
    let viewController: GameCenterAccount.PlatformViewController

    func makeNSViewController(context: Context) -> GameCenterAccount.PlatformViewController { viewController }
    func updateNSViewController(_ nsViewController: GameCenterAccount.PlatformViewController, context: Context) {}
}
#endif
