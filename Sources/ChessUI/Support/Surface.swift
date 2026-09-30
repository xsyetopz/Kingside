import ChessContent
import SwiftUI

extension View {
  /// A grouped surface: Liquid Glass where the system has it, a material otherwise.
  func surface(_ style: InterfaceStyle) -> some View {
    modifier(SurfaceModifier(cornerRadius: style.cornerRadius))
  }
}

private struct SurfaceModifier: ViewModifier {
  let cornerRadius: Double

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(iOS 26, tvOS 26, macOS 26, *) {
      content.glassEffect(.regular, in: shape)
    } else {
      content.background(.regularMaterial, in: shape)
    }
  }
}
