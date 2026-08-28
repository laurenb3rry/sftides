import SwiftUI

struct TideChart: View {
    let curve: [TideSample]
    let slacks: [SlackWindow]
    let window: (start: Date, end: Date)
    let showsDayLines: Bool
    let now: Date
    @Binding var marker: Date

    private let canvasHeight: CGFloat = 152
    private let axisHeight: CGFloat = 16
    /// Keeps the curve and the r=5.5 marker dot clear of the top and bottom edges.
    private let inset: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let width = geometry.size.width
                plot(width: width)
                    .contentShape(Rectangle())
                    .gesture(drag(width: width))
                    .simultaneousGesture(doubleTap)
            }
            .frame(height: canvasHeight)
            axis
        }
    }

    // MARK: - Plot

    private func plot(width: CGFloat) -> some View {
        let range = heightRange

        return ZStack(alignment: .topLeading) {
            // Two gridlines at even divisions of the plot height.
            ForEach(1..<3) { division in
                line(from: CGPoint(x: 0, y: canvasHeight * CGFloat(division) / 3),
                     to: CGPoint(x: width, y: canvasHeight * CGFloat(division) / 3))
                    .stroke(Theme.hairline, lineWidth: 1)
            }

            // Slack windows, full plot height.
            ForEach(visibleSlacks) { slack in
                let start = x(for: max(slack.start, window.start), in: width)
                let end = x(for: min(slack.end, window.end), in: width)
                Rectangle()
                    .fill(Theme.blue.opacity(0.07))
                    .frame(width: max(end - start, 1), height: canvasHeight)
                    .offset(x: start)
            }

            // Local midnight on the interior day boundaries — 72H only.
            if showsDayLines {
                ForEach(1..<3) { day in
                    let x = self.x(for: dayBoundary(day), in: width)
                    line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: canvasHeight))
                        .stroke(Theme.rule, lineWidth: 1)
                }
            }

            curvePath(width: width, range: range)
                .stroke(Theme.blue,
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))

            markerLine(width: width, range: range)
        }
    }

    private func curvePath(width: CGFloat, range: (low: Double, high: Double)) -> Path {
        Path { path in
            for (index, sample) in visibleCurve.enumerated() {
                let point = CGPoint(x: x(for: sample.time, in: width),
                                    y: y(for: sample.height, range: range))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    /// Hidden until there is a curve to sit on — with no data the canvas shows
    /// gridlines only (§5.8).
    @ViewBuilder
    private func markerLine(width: CGFloat, range: (low: Double, high: Double)) -> some View {
        if !visibleCurve.isEmpty {
            let x = x(for: marker, in: width)

            line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: canvasHeight))
                .stroke(Theme.blue, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

            if let height = Conditions.height(at: marker, in: curve) {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 11, height: 11)
                    .position(x: x, y: y(for: height, range: range))
            }
        }
    }

    private func line(from start: CGPoint, to end: CGPoint) -> Path {
        Path { $0.move(to: start); $0.addLine(to: end) }
    }

    // MARK: - Axis

    /// Three labels: the window ends, and `SLACK` under the band nearest the marker.
    /// `SLACK` is anchored to its band, so an end label it would land on top of is
    /// dropped rather than overprinted — the band is the label that matters.
    private var axis: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let start = Self.stamp.string(from: window.start).uppercased()
            let end = Self.stamp.string(from: window.end).uppercased()
            let slackX = nearestSlack.map { x(for: centre(of: $0), in: width) }
            let reach = textWidth("SLACK") / 2 + 8

            ZStack(alignment: .topLeading) {
                HStack {
                    if clear(slackX, of: 22 + textWidth(start) + reach, from: .leading, width) {
                        Text(start)
                    }
                    Spacer(minLength: 8)
                    if clear(slackX, of: 22 + textWidth(end) + reach, from: .trailing, width) {
                        Text(end)
                    }
                }
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 22)

                if let slackX {
                    Text("SLACK")
                        .foregroundStyle(Theme.blue)
                        .position(x: slackX, y: axisHeight / 2)
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .monospacedDigit()
        }
        .frame(height: axisHeight)
    }

    /// SF Mono advance is 0.6em, so a monospaced run measures without a text pass.
    private func textWidth(_ text: String) -> CGFloat { CGFloat(text.count) * 9 * 0.6 }

    private func clear(_ slackX: CGFloat?, of extent: CGFloat,
                       from edge: HorizontalEdge, _ width: CGFloat) -> Bool {
        guard let slackX else { return true }
        return edge == .leading ? slackX > extent : slackX < width - extent
    }

    // MARK: - Gestures (§5.3)

    /// Both drag and tap move the marker. No animation — it tracks the finger exactly.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { marker = time(atX: $0.location.x, width: width) }
    }

    private var doubleTap: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation(.easeOut(duration: 0.25)) {
                marker = Conditions.snap(now, to: window)
            }
        }
    }

    // MARK: - Scales

    private var visibleCurve: [TideSample] {
        curve.filter { $0.time >= window.start && $0.time <= window.end }
    }

    private var visibleSlacks: [SlackWindow] {
        slacks.filter { $0.end >= window.start && $0.start <= window.end }
    }

    private var nearestSlack: SlackWindow? {
        visibleSlacks.min {
            abs(centre(of: $0).timeIntervalSince(marker))
                < abs(centre(of: $1).timeIntervalSince(marker))
        }
    }

    private func centre(of slack: SlackWindow) -> Date {
        slack.start.addingTimeInterval(slack.end.timeIntervalSince(slack.start) / 2)
    }

    private var heightRange: (low: Double, high: Double) {
        let heights = visibleCurve.map(\.height)
        guard let low = heights.min(), let high = heights.max(), high > low else {
            return (0, 1)
        }
        return (low, high)
    }

    private func x(for time: Date, in width: CGFloat) -> CGFloat {
        let span = window.end.timeIntervalSince(window.start)
        return width * CGFloat(time.timeIntervalSince(window.start) / span)
    }

    private func y(for height: Double, range: (low: Double, high: Double)) -> CGFloat {
        let fraction = (height - range.low) / (range.high - range.low)
        return canvasHeight - inset - CGFloat(fraction) * (canvasHeight - inset * 2)
    }

    /// Inverse of `x(for:in:)`, clamped to the window and snapped to the nearest sample.
    private func time(atX x: CGFloat, width: CGFloat) -> Date {
        let span = window.end.timeIntervalSince(window.start)
        let fraction = max(0, min(1, x / width))
        return Conditions.snap(window.start.addingTimeInterval(span * fraction), to: window)
    }

    private func dayBoundary(_ day: Int) -> Date {
        window.start.addingTimeInterval(Double(day) * 86_400)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()
}
