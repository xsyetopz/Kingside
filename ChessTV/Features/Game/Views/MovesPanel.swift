import SwiftUI

// Numbered move list: shaded alternate rows, white and black SAN columns, the latest move
// in a light pill. Scrolls itself to the newest row; it is not focusable.

struct MovesPanel: View {
    let rows: [MoveRow]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        MoveRowView(row: row, latest: latestSide(of: row))
                            .id(row.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay {
                if rows.isEmpty {
                    Text("No moves yet")
                        .font(ChessFont.bodyRegular)
                        .foregroundStyle(ChessTheme.textMuted)
                }
            }
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChange(of: rows.last) { _, _ in scrollToEnd(proxy, animated: true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Move list")
    }

    /// Which half of `row` holds the latest move, if any.
    private func latestSide(of row: MoveRow) -> MoveRowView.Side? {
        guard row.id == rows.last?.id else { return nil }
        return row.black == nil ? .white : .black
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = rows.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct MoveRowView: View {
    enum Side { case white, black }

    let row: MoveRow
    let latest: Side?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(row.number).")
                .font(ChessFont.bodyRegular.monospacedDigit())
                .foregroundStyle(ChessTheme.textMuted)
                .frame(width: 76, alignment: .leading)
            MoveCell(san: row.white, isLatest: latest == .white)
            MoveCell(san: row.black ?? "", isLatest: latest == .black)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(row.number.isMultiple(of: 2) ? Color.white.opacity(0.04) : .clear)
    }
}

private struct MoveCell: View {
    let san: String
    let isLatest: Bool

    var body: some View {
        Text(san)
            .font(isLatest ? ChessFont.body.weight(.bold) : ChessFont.body)
            .foregroundStyle(isLatest ? ChessTheme.textPrimary : ChessTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background {
                if isLatest {
                    Capsule().fill(Color.white.opacity(0.2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
