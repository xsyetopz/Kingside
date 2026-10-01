import ChessContent
import SwiftUI

extension View {
  /// A grouped content panel on a material. Liquid Glass is for the floating control layer, not
  /// for text the user reads.
  func contentPanel(_ style: InterfaceStyle) -> some View {
    background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    )
  }
}
