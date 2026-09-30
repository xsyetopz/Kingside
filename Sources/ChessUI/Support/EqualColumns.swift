import SwiftUI

/// Buttons in two equal columns, with a last odd one across both. When the widest button does not
/// fit in half the width, as with a long translation, all of them go in one column instead, so no
/// label is cut off.
struct EqualColumns: Layout {
    /// Space between cells; `nil` uses the system spacing between the views.
    var spacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width, subviews: subviews)
        let height = rows.frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? rows.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, rows.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    /// Each subview's frame, and the width used when none was proposed.
    private func rows(width: CGFloat?, subviews: Subviews) -> (frames: [CGRect], width: CGFloat) {
        guard !subviews.isEmpty else { return ([], 0) }
        let gap = spacing ?? subviews[0].spacing.distance(to: subviews[0].spacing, along: .horizontal)
        let rowGap = spacing ?? subviews[0].spacing.distance(to: subviews[0].spacing, along: .vertical)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let total = width ?? 2 * widest + gap
        let perRow = 2 * widest + gap <= total ? 2 : 1

        var frames: [CGRect] = []
        var y: CGFloat = 0
        var index = 0
        while index < subviews.count {
            let count = min(perRow, subviews.count - index)
            let cellWidth = count == 2 ? (total - gap) / 2 : total
            let heights = (index..<index + count).map {
                subviews[$0].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            }
            let rowHeight = heights.max() ?? 0
            for column in 0..<count {
                frames.append(CGRect(x: CGFloat(column) * (cellWidth + gap), y: y, width: cellWidth, height: rowHeight))
            }
            y += rowHeight + rowGap
            index += count
        }
        return (frames, total)
    }
}
