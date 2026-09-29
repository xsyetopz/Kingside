import SwiftUI
import ChessCore

// Annotation overlays for hints and game review, passed to `ChessBoardView` / `ChessBoardDisplay`.
// - `BoardArrow(from: e2, to: e4, color: BoardArrow.hint)`: thick translucent arrow with a
//   triangular head; knight jumps are drawn as an L. `opacity` applies to the whole arrow.
// - `BoardBadge(square: e4, content: .text("!!"), color: .teal)` or `.symbol("star.fill")`:
//   a small circular badge at the top-right corner of a square.
// The drawing views take the geometry from the board; callers only build the values.

struct BoardArrow: Hashable {
    var from: Square
    var to: Square
    var color: Color = BoardArrow.hint
    var opacity: Double = 0.8

    /// Orange, the default for hints and user arrows.
    static let hint = Color(hex: 0xFFAA00)
    /// Green, for a best-move arrow.
    static let best = Color(hex: 0x81B64C)
}

struct BoardBadge: Hashable {
    enum Content: Hashable {
        case text(String)
        case symbol(String)
    }

    var square: Square
    var content: Content
    var color: Color
}

/// Draws `arrows` on a board of `squareSize`; `point(for:)` maps a square to its display center.
struct BoardArrowsLayer: View {
    let arrows: [BoardArrow]
    let squareSize: CGFloat
    let point: (Square) -> CGPoint

    var body: some View {
        ZStack {
            ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
                BoardArrowShape(points: path(for: arrow), squareSize: squareSize)
                    .fill(arrow.color)
                    .compositingGroup()
                    .opacity(arrow.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func path(for arrow: BoardArrow) -> [CGPoint] {
        let start = point(arrow.from)
        let end = point(arrow.to)
        let df = abs(arrow.to.file - arrow.from.file)
        let dr = abs(arrow.to.rank - arrow.from.rank)
        guard (df == 1 && dr == 2) || (df == 2 && dr == 1) else { return [start, end] }
        // Knight jump: travel the long leg first, then turn.
        let corner = df == 2 ? CGPoint(x: end.x, y: start.y) : CGPoint(x: start.x, y: end.y)
        return [start, corner, end]
    }
}

/// A filled polyline arrow. Segments overlap at joints; the caller flattens them with
/// `compositingGroup()` before applying opacity so overlaps don't darken.
struct BoardArrowShape: Shape {
    let points: [CGPoint]
    let squareSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        let halfWidth = squareSize * 0.11
        let headHalfWidth = squareSize * 0.27
        let headLength = squareSize * 0.42

        for index in 0..<(points.count - 1) {
            var start = points[index]
            var end = points[index + 1]
            guard let dir = unit(from: start, to: end) else { continue }
            let isLast = index == points.count - 2
            if isLast {
                end = CGPoint(x: end.x - dir.x * headLength, y: end.y - dir.y * headLength)
            } else {
                // Square joint so the turn has no notch.
                end = CGPoint(x: end.x + dir.x * halfWidth, y: end.y + dir.y * halfWidth)
            }
            if index == 0 {
                // Start a little off-center so the arrow does not hide the origin piece entirely.
                start = CGPoint(x: start.x + dir.x * squareSize * 0.2, y: start.y + dir.y * squareSize * 0.2)
            }
            let normal = CGPoint(x: -dir.y, y: dir.x)
            path.addLines([
                offset(start, normal, halfWidth), offset(end, normal, halfWidth),
                offset(end, normal, -halfWidth), offset(start, normal, -halfWidth)
            ])
            path.closeSubpath()
        }

        let tip = points[points.count - 1]
        if let dir = unit(from: points[points.count - 2], to: tip) {
            let base = CGPoint(x: tip.x - dir.x * headLength, y: tip.y - dir.y * headLength)
            let normal = CGPoint(x: -dir.y, y: dir.x)
            path.addLines([offset(base, normal, headHalfWidth), tip, offset(base, normal, -headHalfWidth)])
            path.closeSubpath()
        }
        return path
    }

    private func unit(from a: CGPoint, to b: CGPoint) -> CGPoint? {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private func offset(_ p: CGPoint, _ normal: CGPoint, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: p.x + normal.x * distance, y: p.y + normal.y * distance)
    }
}

/// Draws `badges` at the top-right corner of their squares.
struct BoardBadgesLayer: View {
    let badges: [BoardBadge]
    let squareSize: CGFloat
    let point: (Square) -> CGPoint

    var body: some View {
        ZStack {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                let center = point(badge.square)
                BoardBadgeView(badge: badge, diameter: squareSize * 0.4)
                    .position(x: center.x + squareSize * 0.36, y: center.y - squareSize * 0.36)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A single circular badge; also usable outside the board (e.g. in a move list).
struct BoardBadgeView: View {
    let badge: BoardBadge
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(badge.color)
            switch badge.content {
            case .text(let text):
                Text(text)
                    .font(.system(size: diameter * (text.count > 1 ? 0.46 : 0.6), weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, diameter * 0.08)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: diameter * 0.5, weight: .heavy))
            }
        }
        .foregroundStyle(.white)
        .frame(width: diameter, height: diameter)
        .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1.5, diameter * 0.06)) }
        .shadow(color: .black.opacity(0.4), radius: diameter * 0.08, y: diameter * 0.05)
        .accessibilityHidden(true)
    }
}
