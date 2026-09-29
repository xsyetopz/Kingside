import SwiftUI

/// A label whose icon sits in a fixed-width column, so titles stacked in a list start at the
/// same x even though SF Symbols differ in width.
struct AlignedIconLabelStyle: LabelStyle {
    var iconWidth: CGFloat
    var spacing: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon.frame(width: iconWidth)
            configuration.title
        }
    }
}

extension LabelStyle where Self == AlignedIconLabelStyle {
    static func alignedIcon(width: CGFloat) -> AlignedIconLabelStyle { AlignedIconLabelStyle(iconWidth: width) }
}
