import SwiftUI

/// White chat bubble with a tail on its leading edge, pointing at an avatar to its left.
struct SpeechBubble: View {
    let text: String
    var font: Font = ChessFont.body

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(ChessTheme.clockActiveText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .leading) {
                BubbleTail()
                    .fill(.white)
                    .frame(width: 16, height: 22)
                    .offset(x: -14)
            }
            .padding(.leading, 14)
            .animation(.easeOut(duration: 0.2), value: text)
            .accessibilityLabel(text)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
