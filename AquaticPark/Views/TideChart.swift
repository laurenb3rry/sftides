import SwiftUI

/// The main element of the screen. It takes whatever height the header, conditions
/// and links leave it rather than a fixed canvas.
///
/// Slack windows are no longer drawn. Slack is read off the state word that
/// `ContentView` sits in the bottom-left corner, which means the only way to see it
/// is to scrub the marker across the window.
struct TideChart: View {
    let curve: [TideSample]
    let window: (start: Date, end: Date)
    /// 72H: ticks land on local midnight, so they double as the day boundaries.
    let showsDayLines: Bool
    let now: Date
    @Binding var marker: Date

    /// Reserved below the plot for the time axis. `ContentView` needs it to sit its
    /// bottom-left overlay inside the plot rather than on top of the axis.
    static let axisHeight: CGFloat = 26

    /// The plot band inside the canvas. The top inset clears the range toggle and
    /// the height readout, so the curve never runs under either.
    private let insetTop: CGFloat = 74
    private let insetBottom: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let canvas = max(geometry.size.height - Self.axisHeight, 1)
            VStack(spacing: 0) {
                plot(width: width, canvas: canvas)
                    .frame(height: canvas)
                    .contentShape(Rectangle())
                    .gesture(drag(width: width))
                    .simultaneousGesture(doubleTap)
                axis(width: width)
                    .frame(height: Self.axisHeight)
            }
        }
    }

    // MARK: - Plot

    private func plot(width: CGFloat, canvas: CGFloat) -> some View {
        let band = self.band(canvas)
        let range = heightRange

        return ZStack(alignment: .topLeading) {
            // Two gridlines at even divisions of the plot band.
            ForEach(1..<3) { division in
                let y = band.top + (band.bottom - band.top) * CGFloat(division) / 3
                line(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y))
                    .stroke(Theme.hairline, lineWidth: 1)
            }

            ForEach(ticks, id: \.self) { tick in
                let x = self.x(for: tick, in: width)
                line(from: CGPoint(x: x, y: band.top), to: CGPoint(x: x, y: band.bottom))
                    .stroke(showsDayLines ? Theme.rule : Theme.hairline, lineWidth: 1)
            }

            heightLabels(band: band, range: range)

            curvePath(width: width, band: band, range: range)
                .stroke(Theme.blue,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            crosshair(width: width, band: band, range: range)
        }
    }

    private func curvePath(width: CGFloat, band: Band,
                           range: (low: Double, high: Double)) -> Path {
        Path { path in
            for (index, sample) in visibleCurve.enumerated() {
                let point = CGPoint(x: x(for: sample.time, in: width),
                                    y: y(for: sample.height, band: band, range: range))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    /// Three heights down the left edge, turned on their side so they stay out of
    /// the plot. Read off the visible curve, so they are always real values.
    @ViewBuilder
    private func heightLabels(band: Band, range: (low: Double, high: Double)) -> some View {
        if !visibleCurve.isEmpty {
            ForEach([range.high, (range.low + range.high) / 2, range.low], id: \.self) { value in
                Text(String(format: "%+.1f", value))
                    .font(.system(size: 8.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .position(x: 11, y: y(for: value, band: band, range: range))
            }
        }
    }

    /// A full-height vertical and a full-width horizontal crossing on the curve.
    /// Hidden until there is a curve to sit on — with no data the canvas shows
    /// gridlines only (§5.8).
    @ViewBuilder
    private func crosshair(width: CGFloat, band: Band,
                           range: (low: Double, high: Double)) -> some View {
        if !visibleCurve.isEmpty, let height = Conditions.height(at: marker, in: curve) {
            let x = self.x(for: marker, in: width)
            let y = self.y(for: height, band: band, range: range)

            line(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y))
                .stroke(Theme.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

            line(from: CGPoint(x: x, y: band.top - 8), to: CGPoint(x: x, y: band.bottom + 4))
                .stroke(Theme.ink, lineWidth: 1.6)

            Circle()
                .fill(Theme.bg)
                .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                .frame(width: 12, height: 12)
                .position(x: x, y: y)
        }
    }

    private func line(from start: CGPoint, to end: CGPoint) -> Path {
        Path { $0.move(to: start); $0.addLine(to: end) }
    }

    // MARK: - Axis

    /// Tick labels plus the marker's own time in full ink. A tick the marker label
    /// would land on top of is dropped — the marker is the label that matters.
    private func axis(width: CGFloat) -> some View {
        let markerX = x(for: marker, in: width)

        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { tick in
                let x = self.x(for: tick, in: width)
                if abs(x - markerX) >= 34, x > 24, x < width - 24 {
                    Text(tickStamp.string(from: tick).uppercased())
                        .foregroundStyle(Theme.inkFaint)
                        .position(x: x, y: Self.axisHeight / 2)
                }
            }

            if !visibleCurve.isEmpty {
                Text(Self.markerStamp.string(from: marker).uppercased())
                    .foregroundStyle(Theme.ink)
                    .position(x: min(max(markerX, 32), width - 32), y: Self.axisHeight / 2)
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .monospacedDigit()
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

    private typealias Band = (top: CGFloat, bottom: CGFloat)

    private func band(_ canvas: CGFloat) -> Band {
        (insetTop, max(canvas - insetBottom, insetTop + 1))
    }

    private var visibleCurve: [TideSample] {
        curve.filter { $0.time >= window.start && $0.time <= window.end }
    }

    /// Whole hours inside the window: every sixth in 24H, local midnight in 72H.
    private var ticks: [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = API.zone
        let every = showsDayLines ? 24 : 6
        var result: [Date] = []
        calendar.enumerateDates(startingAfter: window.start,
                                matching: DateComponents(minute: 0, second: 0),
                                matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date < window.end else { stop = true; return }
            if calendar.component(.hour, from: date) % every == 0 { result.append(date) }
        }
        return result
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

    private func y(for height: Double, band: Band, range: (low: Double, high: Double)) -> CGFloat {
        let fraction = (height - range.low) / (range.high - range.low)
        return band.bottom - CGFloat(fraction) * (band.bottom - band.top)
    }

    /// Inverse of `x(for:in:)`, clamped to the window and snapped to the nearest sample.
    private func time(atX x: CGFloat, width: CGFloat) -> Date {
        let span = window.end.timeIntervalSince(window.start)
        let fraction = max(0, min(1, x / width))
        return Conditions.snap(window.start.addingTimeInterval(span * fraction), to: window)
    }

    private var tickStamp: DateFormatter { showsDayLines ? Self.dayStamp : Self.hourStamp }

    private static let hourStamp = stamp("h a")
    private static let dayStamp = stamp("EEE")
    private static let markerStamp = stamp("h:mm a")

    private static func stamp(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = format
        return formatter
    }
}
