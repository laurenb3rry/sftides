import SwiftUI

/// Every low, high, and slack from 6 hours before the marker to 18 hours after
/// (§5.6). Slacks sitting among the extrema is the point — slack is the event
/// being planned around and it does not coincide with high or low water.
struct TideTable: View {
    let extremes: [TideExtreme]
    let slacks: [SlackWindow]
    let marker: Date

    private enum Event: Identifiable {
        case tide(TideExtreme)
        case slack(SlackWindow)

        /// A slack is a span, so it lists at the moment the window opens.
        var time: Date {
            switch self {
            case .tide(let extreme): extreme.time
            case .slack(let window): window.start
            }
        }
        var id: Date { time }
    }

    var body: some View {
        VStack(spacing: 0) {
            if events.isEmpty { placeholder }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                switch event {
                case .tide(let extreme): tideRow(extreme)
                case .slack(let window): slackRow(window)
                }
            }
        }
    }

    private var events: [Event] {
        let start = marker.addingTimeInterval(-6 * 3600)
        let end = marker.addingTimeInterval(18 * 3600)
        let tides = extremes.map(Event.tide)
        let windows = slacks.map(Event.slack)
        return (tides + windows)
            .filter { $0.time >= start && $0.time <= end }
            .sorted { $0.time < $1.time }
    }

    // MARK: - Rows

    /// Holds the section open before any data arrives — without a row the two blue
    /// rules bounding it would stack into a single 4pt line (§5.8).
    private var placeholder: some View {
        HStack(spacing: 0) {
            Text("—")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 22)
    }

    private func tideRow(_ extreme: TideExtreme) -> some View {
        row(time: extreme.time,
            label: extreme.type == .high ? "HIGH" : "LOW",
            value: String(format: "%.2f ft", extreme.height),
            timeColor: Theme.ink, labelColor: Theme.inkMuted)
    }

    private func slackRow(_ window: SlackWindow) -> some View {
        let minutes = Int((window.end.timeIntervalSince(window.start) / 60).rounded())
        // No right column: the window duration in the label is the informative
        // number, and the velocity inside a slack window is zero by definition.
        return row(time: window.start,
                   label: "SLACK / \(minutes) MIN",
                   value: nil,
                   timeColor: Theme.blue, labelColor: Theme.blue)
            .background(Theme.slackTint)
    }

    private func row(time: Date, label: String, value: String?,
                     timeColor: Color, labelColor: Color) -> some View {
        HStack(spacing: 0) {
            Text(Self.clock.string(from: time))
                .font(.system(size: 13, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(width: 64, alignment: .leading)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.8)
                .monospacedDigit()
                .foregroundStyle(labelColor)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecond)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 22)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
