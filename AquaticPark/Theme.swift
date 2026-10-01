import SwiftUI

enum Theme {
    // MARK: - Ink

    static let paper       = Color(hex: 0xF4F1E8)   // the sheet; no gradients, no grid
    static let ink         = Color(hex: 0x16161A)   // printed type, curve, rules
    static let mute        = Color(hex: 0x7B7870)   // labels, axes, the quieter route
    static let spot        = Color(hex: 0x1A3A8F)   // the only accent: halftone, good cells, hand
    static let hair        = Color(hex: 0x16161A).opacity(0.13)   // row rules
    static let faint       = Color(hex: 0x16161A).opacity(0.14)   // chart gridlines

    // MARK: - Type
    //
    // Three printed voices and one written one. Didot sets numbers, Baskerville sets
    // words, monospace sets the small caps labels, and Lauren's hand sets live values.

    static func display(_ size: CGFloat) -> Font { .custom("Didot", size: size) }
    static func serif(_ size: CGFloat) -> Font { .custom("Baskerville", size: size) }
    static func micro(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

    /// The handwriting has a smaller x-height than the monospace it replaces, so a slot
    /// set at `printed` points needs the hand drawn larger to read as the same size.
    /// Picked by eye — the four faces all report identical (default) vertical metrics,
    /// so there is nothing in the files to compute it from.
    /// ponytail: one global multiplier. Per-face values if one reads lighter than the rest.
    static let handMultiplier: CGFloat = 1.35
    static func hand(_ printed: CGFloat) -> CGFloat { printed * handMultiplier }

    /// Letters and digits are all the handwriting fonts contain, so punctuation is set
    /// in the printed serif at a size that sits with it rather than falling back to the
    /// system face. See `HandwritingText`.
    static let handPunctuationRatio: CGFloat = 0.74

    // MARK: - Metrics

    static let margin: CGFloat = 26
    static let labelTracking: CGFloat = 1.3
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
