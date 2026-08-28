import SwiftUI

/// The four-across strip (§5.5). Everything reads at the marker except the water
/// temperature, which NOAA observes but does not forecast — see `waterEstimated`.
struct ConditionsStrip: View {
    let water: Double?
    /// Marker is more than an hour ahead of now, so the water reading is the last
    /// observation carried forward rather than a value for the marker (§5.4).
    let waterEstimated: Bool
    let weather: WeatherHour?

    var body: some View {
        WeightedRow(weights: [1, 0.8, 1, 0.9]) {
            cell("WATER", leading: 16, divider: false) { waterValue }
            cell("AIR", leading: 14, divider: true) { airValue }
            cell("WIND", leading: 14, divider: true) { windValue }
            cell("UV \(uvIndex)", leading: 14, divider: true) { glyph }
        }
    }

    // MARK: - Cells

    private func cell(_ label: String, leading: CGFloat, divider: Bool,
                      @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: 0) {
            if divider {
                Rectangle()
                    .fill(Theme.rule)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 9.5, design: .monospaced))
                    .tracking(0.76)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkMuted)
                value()
            }
            .padding(.leading, leading)
            .padding(.vertical, 16)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var waterValue: some View {
        if let water {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(String(format: waterEstimated ? "~%.1f°" : "%.1f°", water))
                    .font(.system(size: 20))
                    .monospacedDigit()
                    .foregroundStyle(waterEstimated ? Theme.inkMuted : Theme.ink)
                if waterEstimated {
                    Text("EST")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        } else {
            missing
        }
    }

    @ViewBuilder private var airValue: some View {
        if let air = weather?.airTemperature {
            value("\(Int(air.rounded()))°")
        } else {
            missing
        }
    }

    @ViewBuilder private var windValue: some View {
        if let weather {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                value("\(Int(weather.windSpeed.rounded()))")
                Text(heading(weather.windDirection))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkMuted)
            }
        } else {
            missing
        }
    }

    /// Glyph only, no text — the UV number rides in this cell's label instead.
    @ViewBuilder private var glyph: some View {
        if let name = weather.flatMap({ symbol(for: $0.weatherCode) }) {
            Image(systemName: name)
                .font(.system(size: 23))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Theme.ink)
        } else {
            missing
        }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
    }

    private var missing: some View { value("—") }

    // MARK: - Formatting

    private var uvIndex: String {
        guard let uv = weather?.uvIndex else { return "—" }
        return String(Int(uv.rounded()))
    }

    private func heading(_ degrees: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((degrees / 45).rounded()) % 8]
    }

    /// WMO weather code to SF Symbol (§5.5). An unlisted code gets no glyph rather
    /// than a stand-in — the strip shows `—` instead.
    private func symbol(for code: Int) -> String? {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...57, 61...67, 80...82: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt.rain"
        default: nil
        }
    }
}

/// `HStack` has no notion of flex weights, so the §5.5 ratios need a layout of
/// their own. Height is the tallest cell; each cell is offered the full height so
/// its leading divider can span the strip.
private struct WeightedRow: Layout {
    let weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.replacingUnspecifiedDimensions().width,
               height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let total = weights.reduce(0, +)
        var x = bounds.minX
        for (subview, weight) in zip(subviews, weights) {
            let width = bounds.width * weight / total
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}
