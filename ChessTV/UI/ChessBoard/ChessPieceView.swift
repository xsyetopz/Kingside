import SwiftUI
import ChessCore

/// ChessTV's original, resolution-independent piece set. The geometry is drawn
/// in normalized coordinates so it remains crisp on both 720p and 1080p TVs.
struct ChessPieceView: View {
    let piece: Piece
    let theme: PieceTheme
    let isSelected: Bool
    let isFocused: Bool
    let isLegalTarget: Bool
    let isMoving: Bool
    let pulse: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                if isSelected || isFocused || isLegalTarget {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [interactionColor.opacity(0.42), interactionColor.opacity(0.08), .clear],
                                center: .center,
                                startRadius: size * 0.05,
                                endRadius: size * 0.48
                            )
                        )
                        .scaleEffect(isSelected && pulse ? 1.14 : 0.96)
                        .blur(radius: size * 0.025)

                    Circle()
                        .stroke(interactionColor.opacity(isSelected ? 0.78 : 0.45), lineWidth: max(1.5, size * 0.022))
                        .scaleEffect(isSelected && pulse ? 0.92 : 0.82)
                }

                Ellipse()
                    .fill(.black.opacity(isSelected || isFocused ? 0.52 : 0.34))
                    .frame(width: size * 0.54, height: size * 0.12)
                    .blur(radius: size * 0.025)
                    .offset(y: size * 0.38)

                ThreeDPieceSprite(assetName: spriteAssetName, index: spriteIndex)
                    .frame(width: size * 0.60, height: size * 0.94)
                    .overlay {
                        if isSelected || isFocused {
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.36), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .offset(x: pulse ? size * 0.20 : -size * 0.20)
                            .blendMode(.screen)
                            .mask {
                                ThreeDPieceSprite(assetName: spriteAssetName, index: spriteIndex)
                            }
                        }
                    }
            }
            .scaleEffect(isMoving ? 1.12 : isSelected ? 1.16 : isFocused ? 1.09 : 1)
            .offset(
                y: isMoving
                    ? -size * 0.12
                    : isSelected
                        ? (pulse ? -size * 0.065 : -size * 0.030)
                        : isFocused ? -size * 0.026 : 0
            )
            .rotation3DEffect(
                .degrees(isMoving ? -12 : isSelected ? -9 : isFocused ? -5 : 0),
                axis: (x: 1, y: pulse ? -0.34 : 0.34, z: 0),
                perspective: 0.28
            )
            .shadow(
                color: isMoving ? ChessTheme.accent.opacity(0.70) : glow,
                radius: isMoving ? size * 0.17 : isSelected ? size * 0.15 : isFocused ? size * 0.09 : size * 0.035,
                y: isMoving ? size * 0.10 : size * 0.018
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.70), value: isSelected)
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: isFocused)
            .animation(.interpolatingSpring(mass: 0.72, stiffness: 250, damping: 10, initialVelocity: 1.8), value: isMoving)
            .animation(.easeInOut(duration: 1.05), value: pulse)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var spriteAssetName: String {
        piece.color == .white ? "ChessPiecesIvory3D" : "ChessPiecesBlack3D"
    }

    private var spriteIndex: Int {
        switch piece.type {
        case .pawn: 0
        case .knight: 1
        case .bishop: 2
        case .rook: 3
        case .queen: 4
        case .king: 5
        }
    }

    private var fill: LinearGradient {
        let colors: [Color]
        switch (theme, piece.color) {
        case (.modern, .white): colors = [Color(red: 1.00, green: 0.99, blue: 0.92), Color(red: 0.73, green: 0.82, blue: 0.84)]
        case (.modern, .black): colors = [Color(red: 0.20, green: 0.27, blue: 0.34), Color(red: 0.035, green: 0.055, blue: 0.085)]
        case (.classic, .white): colors = [Color(red: 1.00, green: 0.98, blue: 0.80), Color(red: 0.94, green: 0.82, blue: 0.49), Color(red: 0.66, green: 0.48, blue: 0.24)]
        case (.classic, .black): colors = [Color(red: 0.30, green: 0.31, blue: 0.30), Color(red: 0.045, green: 0.05, blue: 0.045), Color.black]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var outline: Color {
        piece.color == .white ? Color(red: 0.48, green: 0.34, blue: 0.16).opacity(0.72) : .black.opacity(0.95)
    }

    private var detail: Color {
        piece.color == .white ? Color(red: 0.34, green: 0.22, blue: 0.09).opacity(0.52) : Color.white.opacity(0.38)
    }

    private var glow: Color {
        if isSelected { return ChessTheme.selected.opacity(0.9) }
        if isFocused { return ChessTheme.accent.opacity(0.74) }
        if isLegalTarget { return ChessTheme.legal.opacity(0.58) }
        return .black.opacity(0.5)
    }

    private var interactionColor: Color {
        if isSelected { return ChessTheme.selected }
        if isLegalTarget { return ChessTheme.legal }
        return ChessTheme.accent
    }
}

private struct ThreeDPieceSprite: View {
    let assetName: String
    let index: Int

    var body: some View {
        GeometryReader { proxy in
            Image(assetName)
                .resizable()
                .frame(width: proxy.size.width * 6, height: proxy.size.height)
                .offset(x: -CGFloat(index) * proxy.size.width)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct PieceSilhouette: Shape {
    let type: PieceType

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0 / 100, y: rect.minY + rect.height * $1 / 100)
        }
        let box: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect = {
            CGRect(x: rect.minX + rect.width * $0 / 100,
                   y: rect.minY + rect.height * $1 / 100,
                   width: rect.width * $2 / 100,
                   height: rect.height * $3 / 100)
        }

        switch type {
        case .pawn:
            path.addEllipse(in: box(35, 9, 30, 30))
            path.move(to: point(39, 37))
            path.addCurve(to: point(29, 76), control1: point(42, 48), control2: point(32, 60))
            path.addQuadCurve(to: point(71, 76), control: point(50, 84))
            path.addCurve(to: point(61, 37), control1: point(68, 60), control2: point(58, 48))
            path.closeSubpath()

        case .rook:
            path.move(to: point(22, 12))
            path.addLine(to: point(36, 12)); path.addLine(to: point(36, 23))
            path.addLine(to: point(44, 23)); path.addLine(to: point(44, 12))
            path.addLine(to: point(56, 12)); path.addLine(to: point(56, 23))
            path.addLine(to: point(64, 23)); path.addLine(to: point(64, 12))
            path.addLine(to: point(78, 12)); path.addLine(to: point(75, 37))
            path.addLine(to: point(66, 44)); path.addLine(to: point(70, 77))
            path.addLine(to: point(30, 77)); path.addLine(to: point(34, 44))
            path.addLine(to: point(25, 37)); path.closeSubpath()

        case .knight:
            path.move(to: point(27, 76))
            path.addCurve(to: point(34, 51), control1: point(29, 66), control2: point(31, 58))
            path.addCurve(to: point(58, 27), control1: point(39, 43), control2: point(49, 35))
            path.addLine(to: point(45, 12)); path.addCurve(to: point(76, 31), control1: point(61, 13), control2: point(73, 21))
            path.addCurve(to: point(68, 58), control1: point(79, 43), control2: point(75, 51))
            path.addLine(to: point(62, 76)); path.closeSubpath()
            path.move(to: point(34, 48))
            path.addCurve(to: point(17, 59), control1: point(27, 51), control2: point(21, 55))
            path.addCurve(to: point(37, 59), control1: point(22, 66), control2: point(31, 64))
            path.closeSubpath()

        case .bishop:
            path.move(to: point(50, 7))
            path.addCurve(to: point(68, 37), control1: point(68, 19), control2: point(72, 28))
            path.addCurve(to: point(59, 51), control1: point(66, 43), control2: point(62, 47))
            path.addCurve(to: point(70, 77), control1: point(63, 58), control2: point(67, 67))
            path.addLine(to: point(30, 77))
            path.addCurve(to: point(41, 51), control1: point(33, 67), control2: point(37, 58))
            path.addCurve(to: point(32, 37), control1: point(38, 47), control2: point(34, 43))
            path.addCurve(to: point(50, 7), control1: point(28, 27), control2: point(36, 17))
            path.closeSubpath()

        case .queen:
            path.addEllipse(in: box(14, 9, 12, 12)); path.addEllipse(in: box(34, 4, 12, 12))
            path.addEllipse(in: box(54, 4, 12, 12)); path.addEllipse(in: box(74, 9, 12, 12))
            path.move(to: point(20, 19))
            path.addLine(to: point(35, 45)); path.addLine(to: point(40, 14))
            path.addLine(to: point(50, 45)); path.addLine(to: point(60, 14))
            path.addLine(to: point(65, 45)); path.addLine(to: point(80, 19))
            path.addLine(to: point(69, 77)); path.addLine(to: point(31, 77)); path.closeSubpath()

        case .king:
            path.addRoundedRect(in: box(45, 3, 10, 30), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: box(35, 12, 30, 10), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: point(50, 28))
            path.addCurve(to: point(70, 47), control1: point(65, 29), control2: point(74, 37))
            path.addCurve(to: point(60, 57), control1: point(68, 52), control2: point(64, 55))
            path.addLine(to: point(70, 77)); path.addLine(to: point(30, 77)); path.addLine(to: point(40, 57))
            path.addCurve(to: point(30, 47), control1: point(36, 55), control2: point(32, 52))
            path.addCurve(to: point(50, 28), control1: point(26, 37), control2: point(35, 29))
            path.closeSubpath()
        }

        path.addRoundedRect(in: box(22, 75, 56, 10), cornerSize: CGSize(width: rect.width * 0.04, height: rect.height * 0.04))
        path.addRoundedRect(in: box(16, 84, 68, 10), cornerSize: CGSize(width: rect.width * 0.045, height: rect.height * 0.045))
        return path
    }
}

private struct PieceDetails: Shape {
    let type: PieceType

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0 / 100, y: rect.minY + rect.height * $1 / 100)
        }
        let box: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect = {
            CGRect(x: rect.minX + rect.width * $0 / 100,
                   y: rect.minY + rect.height * $1 / 100,
                   width: rect.width * $2 / 100,
                   height: rect.height * $3 / 100)
        }

        path.move(to: point(25, 80)); path.addLine(to: point(75, 80))
        path.move(to: point(22, 89)); path.addLine(to: point(78, 89))

        switch type {
        case .pawn:
            path.move(to: point(36, 55)); path.addQuadCurve(to: point(64, 55), control: point(50, 64))
        case .rook:
            path.move(to: point(31, 37)); path.addLine(to: point(69, 37))
            path.move(to: point(34, 47)); path.addLine(to: point(66, 47))
        case .knight:
            path.addEllipse(in: box(57, 27, 5, 5))
            path.move(to: point(41, 48)); path.addQuadCurve(to: point(61, 54), control: point(52, 43))
        case .bishop:
            path.move(to: point(55, 17)); path.addLine(to: point(42, 39))
            path.move(to: point(38, 49)); path.addQuadCurve(to: point(62, 49), control: point(50, 57))
        case .queen:
            path.move(to: point(28, 46)); path.addQuadCurve(to: point(72, 46), control: point(50, 55))
            path.move(to: point(30, 59)); path.addLine(to: point(70, 59))
        case .king:
            path.move(to: point(35, 48)); path.addQuadCurve(to: point(65, 48), control: point(50, 58))
            path.move(to: point(36, 60)); path.addLine(to: point(64, 60))
        }
        return path
    }
}
