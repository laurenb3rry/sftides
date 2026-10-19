import SwiftUI

/// The four readings a swimmer checks on the walk down. Hybrid setting throughout:
/// the numbers are in her hand, the units stay printed, because a written `°` or `FT`
/// at this size turns into a smudge.
///
/// Set between four corner marks, like registration marks on a proof, rather than in a
/// box or between rules. The readings sit at their natural widths with equal gaps
/// between them, so the spacing is even without any divider doing the work.
struct NowStrip: View {
    let height: Double?
    let rising: Bool?
    let water: Double?
    /// Richmond-only fallback: a `~` is hung off the left of the number.
    var waterEstimated: Bool = false
    let weather: WeatherHour?
    /// Signed knots from `Conditions.velocity` — only the magnitude is shown.
    let knots: Double?
    /// "TIDE NOW" by default; scrubbing the tide figure swaps it for the scrubbed time
    /// so the strip never reads as live when it isn't.
    var label: String = "TIDE NOW"

    /// The readings (about 30pt) and the marks' breathing room above and below them.
    static let viewHeight: CGFloat = 62

    /// Printed numerals are 12pt, so the hand is 12pt scaled by the usual multiplier.
    private let figure: CGFloat = 12
    /// Between the marks and the readings, either side.
    private let inset: CGFloat = 14
    /// Wide enough for "falling", so the gaps after it don't change when it swaps with
    /// "rising"; the word is centred in it.
    private let directionWidth: CGFloat = 58

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(label, clipsLabel: true) {
                // The cell wraps its value in a baseline row; this centre-aligned row sits
                // inside it so the direction can be centred on the numeral.
                HStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        written(height.map(Self.oneDecimal) ?? "—")
                        unit("FT")
                    }
                    // The one word on the sheet that is both written and in colour, because
                    // it is the only reading that is a direction rather than a quantity.
                    // Centred on the numeral's own midline, not its baseline.
                    HandwritingText(text: rising.map { $0 ? "rising" : "falling" } ?? "—",
                                    size: Theme.hand(figure), tracking: 0.2)
                        .foregroundStyle(Theme.spot)
                        .frame(width: directionWidth)
                        .padding(.leading, 6)
                }
            }
            Spacer(minLength: 8)
            cell("WATER") {
                written(water.map(Self.oneDecimal) ?? "—")
                    // An overlay with its trailing edge on the number's leading edge, so
                    // the `~` takes no layout space and nothing beside it moves.
                    .overlay(alignment: .leading) {
                        if waterEstimated {
                            written("~").alignmentGuide(.leading) { $0[.trailing] }
                        }
                    }
                degree()
            }
            Spacer(minLength: 8)
            cell("AIR") {
                written(weather.map { "\(Int($0.airTemperature.rounded()))" } ?? "—")
                degree()
            }
            Spacer(minLength: 8)
            cell("CURRENT") {
                written(knots.map { Self.oneDecimal(abs($0)) } ?? "—")
                unit("KT")
            }
        }
        .padding(.horizontal, inset)
        .frame(height: Self.viewHeight)
        .overlay { CropMarks().stroke(Theme.ink, lineWidth: 1) }
        .padding(.horizontal, Theme.margin)
    }

    /// `clipsLabel` is for the tide cell, whose "TIDE AT 12:34 PM" label grows while
    /// scrubbing: it is given no width, so it runs on past the cell instead of widening it
    /// and nudging the readings beside it.
    @ViewBuilder
    private func cell<Value: View>(_ label: String, clipsLabel: Bool = false,
                                   @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if clipsLabel {
                MicroLabel(text: label, size: 6.8, tracking: 1.1)
                    .fixedSize()
                    .frame(width: 0, alignment: .leading)
            } else {
                MicroLabel(text: label, size: 6.8, tracking: 1.1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 0) { value() }
        }
    }

    private func written(_ text: String) -> some View {
        HandwritingText(text: text, size: Theme.hand(figure), tracking: 0.2)
            .foregroundStyle(Theme.ink)
    }

    /// Raised off the baseline — at this small a size the glyph's own ink sits right down
    /// against it, which reads as a stray mark rather than the usual floating degree sign.
    private func degree() -> some View {
        Text("°").font(Theme.display(figure * 0.6)).foregroundStyle(Theme.mute)
            .baselineOffset(5)
    }

    /// A fixed leading inset rather than a space baked into the string — a space glyph's
    /// width rides on the handwriting font's per-character tracking just like any other
    /// character, so "FT" and "KT" would drift apart under it instead of matching.
    private func unit(_ text: String) -> some View {
        Text(text).font(Theme.micro(7)).tracking(0.42).foregroundStyle(Theme.mute)
            .padding(.leading, 2)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// Four L-shaped corners, 9pt to an arm, standing in for the box they imply.
private struct CropMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 9
        var path = Path()
        for (x, dx) in [(rect.minX, arm), (rect.maxX, -arm)] {
            for (y, dy) in [(rect.minY, arm), (rect.maxY, -arm)] {
                path.move(to: CGPoint(x: x + dx, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + dy))
            }
        }
        return path
    }
}
