import SwiftUI

enum Theme {
    static let blue        = Color(hex: 0x2038F0)   // the only accent, ever
    static let ink         = Color(hex: 0x111114)   // primary text
    static let inkSecond   = Color(hex: 0x75757C)   // secondary text
    static let inkMuted    = Color(hex: 0x8A8A90)   // labels
    static let inkFaint    = Color(hex: 0xB0B0B6)   // axis, sublabels
    static let rule        = Color(hex: 0xE3E3E6)   // 1pt vertical dividers, chart day lines
    static let hairline    = Color(hex: 0xEDEDF0)   // 1pt row separators, chart gridlines
    static let slackTint   = Color(hex: 0xF4F5FE)   // slack row background
    static let pillOff     = Color(hex: 0xD6D6DB)   // unfavorable pill border
    static let bg          = Color.white
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
