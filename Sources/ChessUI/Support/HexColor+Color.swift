import ChessContent
import SwiftUI

extension HexColor {
    /// Red, green, blue, and alpha as 0...1 values.
    var unitComponents: (red: Double, green: Double, blue: Double, alpha: Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255, Double(alpha) / 255)
    }
}

extension Color {
    /// The catalog color as an sRGB SwiftUI color.
    init(_ hex: HexColor) {
        let c = hex.unitComponents
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}
