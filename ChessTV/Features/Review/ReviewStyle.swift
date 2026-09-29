import SwiftUI
import ChessCore

// Colors and icons of the review classifications, plus the small shared review views:
// `ClassificationIcon` (circular badge), `EvaluationBar` (vertical White/Black bar) and
// `EvaluationGraph` (White/Black area chart over plies with markers at errors).

extension MoveClassification {
    var color: Color {
        switch self {
        case .brilliant: Color(hex: 0x26C2A3)
        case .great: Color(hex: 0x5C8BB0)
        case .best: Color(hex: 0x81B64C)
        case .excellent: Color(hex: 0x96BC4B)
        case .good: Color(hex: 0x96AF8B)
        case .book: Color(hex: 0xA88865)
        case .inaccuracy: Color(hex: 0xF7C631)
        case .mistake: Color(hex: 0xFFA459)
        case .miss: Color(hex: 0xFF7769)
        case .blunder: Color(hex: 0xFA412D)
        }
    }

    var badgeContent: BoardBadge.Content {
        switch self {
        case .brilliant: .text("!!")
        case .great: .text("!")
        case .best: .symbol("star.fill")
        case .excellent: .symbol("hand.thumbsup.fill")
        case .good: .symbol("checkmark")
        case .book: .symbol("book.fill")
        case .inaccuracy: .text("?!")
        case .mistake: .text("?")
        case .miss: .symbol("xmark")
        case .blunder: .text("??")
        }
    }

    func badge(on square: Square) -> BoardBadge {
        BoardBadge(square: square, content: badgeContent, color: color)
    }
}

struct ClassificationIcon: View {
    let classification: MoveClassification
    var diameter: CGFloat = 40

    var body: some View {
        BoardBadgeView(badge: classification.badge(on: Square(file: 0, rank: 0)), diameter: diameter)
            .frame(width: diameter, height: diameter)
    }
}

/// Vertical evaluation bar: White's share from the bottom (from the top when flipped).
struct EvaluationBar: View {
    let evaluation: Evaluation?
    var isFlipped = false

    var body: some View {
        let share = evaluation.map(WinProbability.white) ?? 0.5
        let whiteAhead = share >= 0.5
        GeometryReader { proxy in
            ZStack(alignment: isFlipped ? .top : .bottom) {
                Rectangle().fill(Color(hex: 0x403D39))
                Rectangle().fill(Color.white).frame(height: proxy.size.height * share)
            }
            .overlay(alignment: whiteAhead != isFlipped ? .bottom : .top) {
                if let evaluation {
                    Text(EvaluationLabel.text(evaluation).replacingOccurrences(of: "+", with: ""))
                        .font(ChessFont.rounded(18, weight: .heavy))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(whiteAhead ? Color(hex: 0x403D39) : .white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 2)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: share)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// White's win probability after each ply as a white area over a dark background.
struct EvaluationGraph: View {
    /// White's win probability for the start position and after each analysed ply.
    let probabilities: [Double]
    /// Total plies of the game, so the chart keeps its scale while analysis runs.
    let plyCount: Int
    let markers: [(ply: Int, classification: MoveClassification)]
    var highlightedPly: Int?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let step = size.width / CGFloat(max(plyCount, 1))
            let point = { (index: Int, value: Double) in
                CGPoint(x: CGFloat(index) * step, y: size.height * (1 - value))
            }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hex: 0x403D39))
                Path { path in
                    guard !probabilities.isEmpty else { return }
                    path.move(to: CGPoint(x: 0, y: size.height))
                    for (index, value) in probabilities.enumerated() { path.addLine(to: point(index, value)) }
                    path.addLine(to: CGPoint(x: CGFloat(probabilities.count - 1) * step, y: size.height))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.92))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                if let highlightedPly {
                    Rectangle()
                        .fill(ChessTheme.primary.opacity(0.7))
                        .frame(width: 3)
                        .offset(x: CGFloat(highlightedPly) * step - 1.5)
                }
                ForEach(markers, id: \.ply) { marker in
                    if marker.ply < probabilities.count {
                        let center = point(marker.ply, probabilities[marker.ply])
                        Circle()
                            .fill(marker.classification.color)
                            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                            .frame(width: 14, height: 14)
                            .position(center)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
