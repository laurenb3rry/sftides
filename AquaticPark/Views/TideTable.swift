import SwiftUI

/// State B — every low, high, and slack from 6 hours before the marker to 18 hours
/// after, grouped under a day header. No separators. Tapping a row moves the marker.
struct TideTable: View {
    let extremes: [TideExtreme]
    let slacks: [SlackWindow]
    let marker: Date
    let onSelect: (Date) -> Void

    private enum Event: Identifiable {
        case tide(TideExtreme)
        case slack(SlackWindow)

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
            if events.isEmpty {
                placeholder
            } else {
                ForEach(days, id: \.self) { day in
                    dayHeader(day)
                    ForEach(events.filter { self.day(of: $0.time) == day }) { event in
                        switch event {
                        case .tide(let extreme): tideRow(extreme)
                        case .slack(let window): slackRow(window)
                        }
                    }
                }
            }
        }
        .frame(height: Self.height, alignment: .top)
        .clipped()
    }

    /// A fixed slot. How many events fall in the window changes as the marker moves,
    /// and the chart above takes whatever height this section leaves — so the table
    /// reserves room for the busiest window rather than resizing under the graph.
    static let height: CGFloat = 10 * rowHeight + 2 * headerHeight + 16
    private static let rowHeight: CGFloat = 32
    private static let headerHeight: CGFloat = 31

    private var events: [Event] {
        let start = marker.addingTimeInterval(-6 * 3600)
        let end = marker.addingTimeInterval(18 * 3600)
        let tides = extremes.map(Event.tide)
        let windows = slacks.map(Event.slack)
        return (tides + windows)
            .filter { $0.time >= start && $0.time <= end }
            .sorted { $0.time < $1.time }
    }

    /// Days in event order, deduplicated.
    private var days: [String] {
        events.map { day(of: $0.time) }.reduce(into: []) { unique, day in
            if unique.last != day { unique.append(day) }
        }
    }

    // MARK: - Rows

    private func dayHeader(_ day: String) -> some View {
        Text(day)
            .font(.system(size: 9, design: .monospaced))
            .tracking(0.81)
            .foregroundStyle(Theme.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .frame(height: Self.headerHeight, alignment: .bottom)
            .padding(.bottom, 6)
    }

    /// Holds the section open before any data arrives (§5.8).
    private var placeholder: some View {
        row(time: "—", type: "", value: "",
            timeColor: Theme.ink, typeColor: Theme.inkMuted, valueColor: Theme.inkSecond)
    }

    private func tideRow(_ extreme: TideExtreme) -> some View {
        row(time: Self.clock.string(from: extreme.time),
            type: extreme.type == .high ? "HIGH" : "LOW",
            value: String(format: "%.2f ft", extreme.height),
            timeColor: Theme.ink, typeColor: Theme.inkMuted, valueColor: Theme.inkSecond)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(extreme.time) }
    }

    private func slackRow(_ window: SlackWindow) -> some View {
        let minutes = Int((window.end.timeIntervalSince(window.start) / 60).rounded())
        return row(time: Self.clock.string(from: window.start),
                   type: "SLACK", value: "\(minutes) min",
                   timeColor: Theme.blue, typeColor: Theme.blue, valueColor: Theme.blue)
            .background(Theme.slackTint)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(window.start) }
    }

    private func row(time: String, type: String, value: String,
                     timeColor: Color, typeColor: Color, valueColor: Color) -> some View {
        HStack(spacing: 0) {
            Text(time)
                .font(.system(size: 11.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(width: 72, alignment: .leading)
            Text(type)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.72)
                .foregroundStyle(typeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 22)
        .frame(height: Self.rowHeight)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private func day(of time: Date) -> String {
        Self.dayName.string(from: time).uppercased()
    }

    private static let dayName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
