import SwiftUI

/// The five readings a swimmer checks on the walk down. Hybrid setting throughout:
/// the numbers are in her hand, the units stay printed, because a written `°` or `FT`
/// at this size turns into a smudge.
///
/// The row splits exactly in half: the tide reading and its rising/falling word share
/// the left 50% evenly, water/air/current share the right 50% evenly. Both halves are
/// fixed fractions, not natural widths, so a longer "TIDE AT ..." label while scrubbing
/// never nudges anything to its right.
struct NowStrip: View {
    let height: Double?
    let rising: Bool?
    let water: Double?
    let weather: WeatherHour?
    /// Signed knots from `Conditions.velocity` — only the magnitude is shown.
    let knots: Double?
    /// "TIDE NOW" by default; scrubbing the tide figure swaps it for the scrubbed time
    /// so the strip never reads as live when it isn't.
    var label: String = "TIDE NOW"

    static let viewHeight: CGFloat = 54

    /// Printed numerals are 19pt, so the hand is 19pt scaled by the usual multiplier.
    private let figure: CGFloat = 19

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                cell(label) {
                    written(height.map(Self.oneDecimal) ?? "—")
                    unit("FT")
                }
                cell(" ") {
                    // The one word on the sheet that is both written and in colour, because
                    // it is the only reading that is a direction rather than a quantity.
                    HandwritingText(text: rising.map { $0 ? "rising" : "falling" } ?? "—",
                                    size: 22, tracking: 0.2)
                        .foregroundStyle(Theme.spot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 0) {
                cell("WATER", centered: true) {
                    written(water.map(Self.oneDecimal) ?? "—")
                    degree()
                }
                cell("AIR", centered: true) {
                    written(weather.map { "\(Int($0.airTemperature.rounded()))" } ?? "—")
                    degree()
                }
                cell("CURRENT", centered: true) {
                    written(knots.map { Self.oneDecimal(abs($0)) } ?? "—")
                    unit("KT")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 1) }
        .padding(.top, 16)
        .frame(height: Self.viewHeight, alignment: .bottom)
    }

    /// Both halves claim an equal share — the left pair's share is fixed at 50% of the
    /// row regardless of how long `label` gets while scrubbing, so nothing to its right
    /// ever shifts; within each half, every cell claims an equal share in turn.
    @ViewBuilder
    private func cell<Value: View>(_ label: String, centered: Bool = false,
                                   @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 5) {
            MicroLabel(text: label, tracking: 1.22)
            HStack(alignment: .lastTextBaseline, spacing: 0) { value() }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    private func written(_ text: String) -> some View {
        HandwritingText(text: text, size: Theme.hand(figure), tracking: 0.2)
            .foregroundStyle(Theme.ink)
    }

    /// Raised off the baseline — at this small a size the glyph's own ink sits right down
    /// against it, which reads as a stray mark rather than the usual floating degree sign.
    private func degree() -> some View {
        Text("°").font(Theme.display(figure * 0.5)).foregroundStyle(Theme.mute)
            .baselineOffset(6)
    }

    /// A fixed leading inset rather than a space baked into the string — a space glyph's
    /// width rides on the handwriting font's per-character tracking just like any other
    /// character, so "FT" and "KT" would drift apart under it instead of matching.
    private func unit(_ text: String) -> some View {
        Text(text).font(Theme.micro(9)).tracking(0.45).foregroundStyle(Theme.mute)
            .padding(.leading, 2)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
