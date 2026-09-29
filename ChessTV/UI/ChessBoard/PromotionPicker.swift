import SwiftUI
import ChessCore

// Promotion chooser drawn over the board as a vertical white strip on the promotion file.
// Place it as an overlay sized exactly like the board:
//   board.overlay { PromotionPickerOverlay(square: move.to, color: .white, isFlipped: flipped,
//                                          onPick: vm.choosePromotion, onCancel: vm.cancelSelection) }
// The queen sits on the promotion square and gets focus first; Back or the X cancels.
// The board should have input disabled while the picker is shown.

struct PromotionPickerOverlay: View {
    let square: Square
    let color: PieceColor
    let isFlipped: Bool
    var pieceSet: PieceSet = .cburnett
    let onPick: (PieceType) -> Void
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let squareSize = min(proxy.size.width, proxy.size.height) / 8
            let column = isFlipped ? 7 - square.file : square.file
            let row = isFlipped ? square.rank : 7 - square.rank
            let fromTop = row < 4
            ZStack(alignment: fromTop ? .top : .bottom) {
                Color.black.opacity(0.35)
                PromotionPicker(color: color, squareSize: squareSize, fromTop: fromTop, pieceSet: pieceSet, onPick: onPick, onCancel: onCancel)
                    .offset(x: (CGFloat(column) - 3.5) * squareSize)
            }
            .frame(width: squareSize * 8, height: squareSize * 8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The strip itself: queen, knight, rook, bishop and a cancel cell, ordered away from `fromTop`.
struct PromotionPicker: View {
    let color: PieceColor
    let squareSize: CGFloat
    var fromTop = true
    var pieceSet: PieceSet = .cburnett
    let onPick: (PieceType) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: PieceType?
    private static let choices: [PieceType] = [.queen, .knight, .rook, .bishop]

    var body: some View {
        VStack(spacing: 0) {
            if !fromTop { cancelCell }
            ForEach(fromTop ? Self.choices : Self.choices.reversed(), id: \.self) { type in
                Button { onPick(type) } label: {
                    ChessPieceView(piece: Piece(type: type, color: color), pieceSet: pieceSet)
                        .padding(squareSize * 0.06)
                        .frame(width: squareSize, height: squareSize)
                }
                .buttonStyle(PromotionCellStyle())
                .focused($focused, equals: type)
                .accessibilityLabel("Promote to \(type.rawValue)")
            }
            if fromTop { cancelCell }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
        .focusSection()
        .onAppear { focused = .queen }
        .onExitCommand(perform: onCancel)
    }

    private var cancelCell: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: squareSize * 0.22, weight: .bold))
                .foregroundStyle(ChessTheme.textMuted)
                .frame(width: squareSize, height: squareSize * 0.5)
                .background(Color(hex: 0xF1F1F1))
        }
        .buttonStyle(PromotionCellStyle())
        .accessibilityLabel("Cancel promotion")
    }
}

private struct PromotionCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PromotionCell(configuration: configuration)
    }
}

private struct PromotionCell: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .background(isFocused ? Color(hex: 0xD9D9D9) : .clear)
            .overlay { Rectangle().strokeBorder(ChessTheme.primary, lineWidth: isFocused ? 5 : 0) }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}
