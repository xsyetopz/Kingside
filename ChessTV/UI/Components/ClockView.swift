import SwiftUI

// Game clock box: `ClockView(time: 183, isActive: true, isLow: false)`.
// Active: white box, dark text, clock icon. Inactive: dark box, muted text.
// Low time: red box when active, red text when inactive. `time: .infinity` shows "∞".
// Shows h:mm:ss from one hour, m:ss otherwise, and tenths below 10 seconds.

struct ClockView: View {
    let time: TimeInterval
    let isActive: Bool
    let isLow: Bool
    var width: CGFloat = 210

    var body: some View {
        HStack(spacing: 12) {
            if isActive {
                Image(systemName: "clock.fill").font(.system(size: 26, weight: .bold))
            }
            Spacer(minLength: 0)
            Text(formatted).font(ChessFont.clock)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(width: width)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clock \(formatted)\(isActive ? ", running" : "")")
    }

    private var background: Color {
        if isActive { return isLow ? ChessTheme.clockLow : ChessTheme.clockActive }
        return ChessTheme.clockInactive
    }

    private var foreground: Color {
        if isActive { return isLow ? .white : ChessTheme.clockActiveText }
        return isLow ? ChessTheme.lossBright : ChessTheme.clockInactiveText
    }

    private var formatted: String {
        guard time.isFinite else { return "∞" }
        let clamped = max(0, time)
        let whole = Int(clamped)
        if whole >= 3600 {
            return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
        }
        if clamped < 10 {
            return String(format: "0:%04.1f", (clamped * 10).rounded(.down) / 10)
        }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
