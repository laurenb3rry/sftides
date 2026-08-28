import SwiftUI

/// State A — four equal columns, no dividers, no borders. Everything reads at the
/// marker except the water temperature, which NOAA observes but does not forecast —
/// see `waterEstimated`.
struct ConditionsStrip: View {
    let water: Double?
    /// Marker is more than an hour ahead of now, so the water reading is the last
    /// observation carried forward rather than a value for the marker (§5.4).
    let waterEstimated: Bool
    let weather: WeatherHour?

    var body: some View {
        HStack(spacing: 0) {
            column("WATER") { waterValue }
            column("AIR") { airValue }
            column("WIND") { windValue }
            column("UV \(uvIndex)") { glyph }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 34)
    }

    // MARK: - Columns

    private func column(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 7) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.72)
                .monospacedDigit()
                .foregroundStyle(Theme.inkMuted)
            value()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var waterValue: some View {
        if let water {
            // The `~` and the muted ink carry the estimate; no `EST` label.
            Text(String(format: waterEstimated ? "~%.1f°" : "%.1f°", water))
                .font(.system(size: 18, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(waterEstimated ? Theme.inkMuted : Theme.ink)
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
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                value("\(Int(weather.windSpeed.rounded()))")
                Text(heading(weather.windDirection))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.inkMuted)
            }
        } else {
            missing
        }
    }

    /// Glyph only, no text — the UV number rides in this column's label instead.
    @ViewBuilder private var glyph: some View {
        if let name = weather.flatMap({ symbol(for: $0.weatherCode) }) {
            Image(systemName: name)
                .font(.system(size: 20))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Theme.ink)
        } else {
            missing
        }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, design: .monospaced))
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
