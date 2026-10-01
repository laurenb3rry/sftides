import SwiftUI

/// The four readings a swimmer checks on the walk down. Hybrid setting throughout:
/// the numbers are in her hand, the units stay printed, because a written `°` or `FT`
/// at this size turns into a smudge.
struct NowStrip: View {
    let height: Double?
    let rising: Bool?
    let water: Double?
    let weather: WeatherHour?
    /// "TIDE NOW" by default; scrubbing the tide figure swaps it for the scrubbed time
    /// so the strip never reads as live when it isn't.
    var label: String = "TIDE NOW"

    static let viewHeight: CGFloat = 54

    /// Printed numerals are 19pt, so the hand is 19pt scaled by the usual multiplier.
    private let figure: CGFloat = 19

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(label) {
                written(height.map(Self.oneDecimal) ?? "—")
                unit(" FT")
            }
            cell(" ") {
                // The one word on the sheet that is both written and in colour, because
                // it is the only reading that is a direction rather than a quantity.
                HandwritingText(text: rising.map { $0 ? "rising" : "falling" } ?? "—",
                                size: 22, tracking: 0.2)
                    .foregroundStyle(Theme.spot)
            }
            cell("WATER") {
                written(water.map(Self.oneDecimal) ?? "—")
                degree()
            }
            cell("AIR / WIND") {
                written(weather.map { "\(Int($0.airTemperature.rounded()))" } ?? "—")
                degree()
                unit(weather.map {
                    " · \(Int($0.windSpeed.rounded())) " + Self.compass($0.windDirection)
                } ?? "")
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 1) }
        .padding(.top, 16)
        .frame(height: Self.viewHeight, alignment: .bottom)
    }

    private func cell<Value: View>(_ label: String,
                                   @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MicroLabel(text: label, tracking: 1.22)
            HStack(alignment: .lastTextBaseline, spacing: 0) { value() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func written(_ text: String) -> some View {
        HandwritingText(text: text, size: Theme.hand(figure), tracking: 0.2)
            .foregroundStyle(Theme.ink)
    }

    private func degree() -> some View {
        Text("°").font(Theme.display(figure)).foregroundStyle(Theme.mute)
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(Theme.micro(9)).tracking(0.45).foregroundStyle(Theme.mute)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// One or two letters — the strip has no room for "west-southwest".
    private static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees / 45).rounded()) % 8
        return points[(index + 8) % 8]
    }
}
