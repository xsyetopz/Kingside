import ChessContent
import Foundation

/// The game screen's layout decisions and clock text, apart from the views.
enum GameLayout {
    /// Whether the board goes left and the panel right, judged by the space the screen has.
    static func isWide(_ size: CGSize, style: GameLayoutStyle) -> Bool {
        size.height > 0 && size.width / size.height >= style.wideAspectRatio
    }

    /// Remaining time as `m:ss`, or `h:mm:ss` from an hour. Partial seconds round up, so a
    /// clock shows zero only once it has flagged.
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let (hours, minutes, rest) = (total / 3600, total % 3600 / 60, total % 60)
        let padded = rest < 10 ? "0\(rest)" : "\(rest)"
        guard hours > 0 else { return "\(minutes):\(padded)" }
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(padded)"
    }
}
