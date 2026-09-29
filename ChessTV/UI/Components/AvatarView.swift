import SwiftUI

// Rounded-square avatar: `AvatarView(name: "Magnus Carlsen")` shows initials "MC";
// `AvatarView(systemImage: "cpu", color: .indigo)` shows a symbol. With neither, a person icon.
// The background color defaults to one derived from the name so it stays stable per player.

struct AvatarView: View {
    var name: String?
    var systemImage: String?
    var color: Color?
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(color ?? Self.color(for: name))
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: size * 0.5, weight: .semibold))
            } else if let initials, !initials.isEmpty {
                Text(initials).font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.55))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String? {
        name.map { name in
            name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
    }

    private static let palette: [Color] = [
        Color(hex: 0x5D9948), Color(hex: 0x3D7EA6), Color(hex: 0x9C5DB5), Color(hex: 0xC7773A),
        Color(hex: 0xB5485A), Color(hex: 0x4E8C87), Color(hex: 0x7A6A55)
    ]

    private static func color(for name: String?) -> Color {
        guard let name, !name.isEmpty else { return ChessTheme.focusSurface }
        // Stable across launches, unlike `hashValue`.
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
}
