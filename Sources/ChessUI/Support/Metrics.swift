import ChessContent

extension InterfaceStyle {
    /// 1, or `tvSpacingScale` on tvOS, where the screen is viewed from across the room.
    var platformScale: Double {
        #if os(tvOS)
        tvSpacingScale
        #else
        1
        #endif
    }

    /// `spacing` for the current platform.
    var gap: Double { spacing * platformScale }

    /// `sectionSpacing` for the current platform.
    var sectionGap: Double { sectionSpacing * platformScale }
}
