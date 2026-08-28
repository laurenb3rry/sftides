import SwiftUI

struct TideChart: View {
    let curve: [TideSample]
    let window: (start: Date, end: Date)
    let now: Date
    @Binding var marker: Date

    private let canvasHeight: CGFloat = 166
    private let axisHeight: CGFloat = 18
    /// Keeps the curve and the r=6 marker dot clear of the top and bottom edges.
    private let inset: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            label
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

    // MARK: - Section label (§5.3)

    private var label: some View {
        HStack {
            Text("72H PHASE SCHEMATIC")
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(stateWord)
                .foregroundStyle(Theme.blue)
        }
        .font(.system(.caption2, design: .monospaced))
        .tracking(0.9)
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .padding(.bottom, 6)
    }

    private var stateWord: String {
        guard let rising = Conditions.isRising(at: marker, in: curve) else { return "—" }
        return rising ? "RISING" : "FALLING"
    }

    // MARK: - Plot

    private func plot(width: CGFloat) -> some View {
        let range = heightRange

        return ZStack(alignment: .topLeading) {
            // Three gridlines at even divisions of the plot height.
            ForEach(1..<4) { division in
                line(from: CGPoint(x: 0, y: canvasHeight * CGFloat(division) / 4),
                     to: CGPoint(x: width, y: canvasHeight * CGFloat(division) / 4))
                    .stroke(Theme.hairline, lineWidth: 1)
            }

            // Local midnight on the two interior day boundaries.
            ForEach(1..<3) { day in
                let x = self.x(for: dayBoundary(day), in: width)
                line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: canvasHeight))
                    .stroke(Theme.rule, lineWidth: 1)
            }

            curvePath(width: width, range: range)
                .stroke(Theme.blue,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

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
    /// gridlines and day lines only (§5.8).
    @ViewBuilder
    private func markerLine(width: CGFloat, range: (low: Double, high: Double)) -> some View {
        if !visibleCurve.isEmpty {
            let x = x(for: marker, in: width)

            line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: canvasHeight))
                .stroke(Theme.blue, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

            if let height = Conditions.height(at: marker, in: curve) {
                Circle()
                    .fill(Theme.blue)
                    .frame(width: 12, height: 12)
                    .position(x: x, y: y(for: height, range: range))
            }
        }
    }

    private func line(from start: CGPoint, to end: CGPoint) -> Path {
        Path { $0.move(to: start); $0.addLine(to: end) }
    }

    // MARK: - Axis (§5.3)

    private var axis: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(0..<3) { day in
                    Text(dayLabel(day))
                        .foregroundStyle(Theme.inkFaint)
                        .offset(x: x(for: dayBoundary(day), in: geometry.size.width))
                }
                // Anchored to real now, so it stays put while the marker is dragged.
                Text("NOW")
                    .foregroundStyle(Theme.blue)
                    .position(x: x(for: now, in: geometry.size.width), y: axisHeight / 2)
            }
            .font(.system(size: 9.5, design: .monospaced))
        }
        .frame(height: axisHeight)
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

    private func dayLabel(_ day: Int) -> String {
        Self.dayFormatter.string(from: dayBoundary(day)).uppercased()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
