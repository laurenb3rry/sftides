import SwiftUI

/// Tide above, current below, on one shared 24-hour axis — the pairing is the point.
/// The tide curve is the shape of the day; the bars under it are what the Gate is doing
/// inside that shape, and swimmers care about the second one. Drawn as a figure rather
/// than a chart: no boxed plot area, no legend, a halftone fill instead of a gradient.
struct TideFigure: View {
    let curve: [TideSample]
    let samples: [CurrentSample]
    /// Each one gets an X on the zero line; tapping it shades the slack window and
    /// labels it with its span.
    let slacks: [SlackWindow]
    /// Every west or east swim window in range. The halftone goes full colour under them.
    let swims: [ClosedRange<Date>]
    /// The whole range on offer; pinching narrows what is shown within it.
    let fullWindow: (start: Date, end: Date)
    /// Where the dot and the vertical tick are drawn — real "now" until the figure is
    /// scrubbed, then wherever the finger last was.
    let now: Date
    /// Fires with the time under the finger as the figure is dragged, so the caller
    /// can move the marker and update the strip above without the figure owning state.
    var onScrub: ((Date) -> Void)?

    /// Vertical layout, measured up from the bottom of whatever height the figure is
    /// handed: the caption line, then the current strip (21pt each way), then the tide
    /// chart takes everything above it. The chart grows with the figure; the strip doesn't.
    private let captionHeight: CGFloat = 12
    private let stripHalf: CGFloat = 21
    private let knot: CGFloat = 6

    /// The current strip reads as texture, not as 240 separate readings.
    private let bars = 72

    /// Four hours is as far in as the 6-minute data stays worth reading.
    private let minZoomSpan: TimeInterval = 4 * 3600

    @State private var selectedSlack: Date?
    @State private var zoomSpan: TimeInterval?
    @State private var zoomStart = Date()
    /// The shown window when the current pinch began, so the whole pinch is measured
    /// against it rather than compounding frame to frame.
    @State private var pinch: (start: Date, span: TimeInterval)?
    @State private var pinching = false
    /// Tapping the axis hands the finger to the time range: drags shift it, and the
    /// marker is hidden because nothing is being read off the curve. A tap anywhere
    /// on the figure hands it back.
    @State private var shifting = false
    @State private var panBase: Date?

    /// What is on screen: the full range, or the pinched-in slice of it. Everything
    /// below reads this, so scrubbing and drawing stay in step with the zoom.
    private var window: (start: Date, end: Date) {
        guard let zoomSpan, zoomSpan < fullWindow.end.timeIntervalSince(fullWindow.start)
        else { return fullWindow }
        let start = min(max(zoomStart, fullWindow.start),
                        fullWindow.end.addingTimeInterval(-zoomSpan))
        return (start, start.addingTimeInterval(zoomSpan))
    }

    var body: some View {
        GeometryReader { geometry in
            canvas
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Two fingers are a pinch, not a scrub.
                        guard !pinching else { return }
                        if shifting {
                            pan(by: value.translation.width, width: geometry.size.width)
                            return
                        }
                        // A touch that starts on an X or the axis is a tap on it, not a scrub.
                        guard slack(at: value.startLocation, in: geometry.size) == nil,
                              !onAxis(value.startLocation, in: geometry.size) else { return }
                        onScrub?(time(at: value.location.x, width: geometry.size.width))
                    }
                    .onEnded { value in
                        panBase = nil
                        guard hypot(value.translation.width, value.translation.height) < 10
                        else { return }
                        if shifting {
                            shifting = false
                        } else if onAxis(value.startLocation, in: geometry.size) {
                            shifting = true
                        } else if let hit = slack(at: value.startLocation, in: geometry.size) {
                            selectedSlack = selectedSlack == hit.id ? nil : hit.id
                        }
                    })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged(zoom)
                    .onEnded { _ in
                        pinch = nil
                        pinching = false
                    })
        }
        // 24H and 4D are different axes; a zoom from one means nothing on the other.
        .onChange(of: fullWindow.end) {
            zoomSpan = nil
            shifting = false
        }
    }

    /// Keeps the time under the fingers where it started, so the pinch zooms into the
    /// spot it was made over rather than toward the middle.
    private func zoom(_ value: MagnifyGesture.Value) {
        pinching = true
        if pinch == nil { pinch = (window.start, window.end.timeIntervalSince(window.start)) }
        guard let base = pinch else { return }
        let full = fullWindow.end.timeIntervalSince(fullWindow.start)
        let span = min(max(base.span / value.magnification, minZoomSpan), full)
        let anchor = base.start.addingTimeInterval(base.span * value.startAnchor.x)
        zoomSpan = span
        zoomStart = anchor.addingTimeInterval(-span * value.startAnchor.x)
    }

    /// The time axis: the rule and the labels hanging under it.
    private func onAxis(_ point: CGPoint, in size: CGSize) -> Bool {
        let baseline = rows(size.height).baseline
        return point.y > baseline - 6 && point.y < baseline + 20
    }

    /// Drags the zoomed window, finger-with-the-chart: dragging right shows earlier times.
    /// Measured from where the drag began, and clamped to the range on offer.
    private func pan(by translation: CGFloat, width: CGFloat) {
        guard let zoomSpan, width > 0 else { return }
        if panBase == nil { panBase = window.start }
        guard let base = panBase else { return }
        let latest = fullWindow.end.addingTimeInterval(-zoomSpan)
        let start = base.addingTimeInterval(-zoomSpan * Double(translation / width))
        zoomStart = min(max(start, fullWindow.start), latest)
    }

    private func slackX(_ slack: SlackWindow, _ width: CGFloat) -> CGFloat {
        x(slack.time, width)
    }

    private func slack(at point: CGPoint, in size: CGSize) -> SlackWindow? {
        guard abs(point.y - rows(size.height).zero) < 16 else { return nil }
        return slacks.first { abs(slackX($0, size.width) - point.x) < 14 }
    }

    /// The tide chart's baseline sits clear of the flood bars with room for the axis
    /// labels between; its curve fills the rest, down from 10pt under the top.
    private func rows(_ height: CGFloat) -> (baseline: CGFloat, amplitude: CGFloat, zero: CGFloat) {
        let zero = height - captionHeight - stripHalf - 2
        let baseline = zero - stripHalf - 20
        // The curve tops out 28pt down, below the two lines of the slack label.
        return (baseline, baseline - 28, zero)
    }

    private var canvas: some View {
        Canvas { context, size in
            let width = size.width
            let (baseline, amplitude, zero) = rows(size.height)

            for step in 1..<3 {
                let y = 28 + (baseline - 28) * CGFloat(step) / 3
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y))
                                      $0.addLine(to: CGPoint(x: width, y: y)) },
                               with: .color(Theme.faint), lineWidth: 0.6)
            }

            if let (line, area) = tidePath(width: width, baseline: baseline,
                                           amplitude: amplitude) {
                let focus = swims.map { x($0.lowerBound, width)...x($0.upperBound, width) }
                halftone(context, clippedTo: area, width: width, height: baseline, focus: focus)
                context.stroke(line, with: .color(Theme.ink), lineWidth: 1.7)
            }

            if let slack = slacks.first(where: { $0.id == selectedSlack }) {
                let from = max(x(slack.start, width), 0)
                let to = min(x(slack.end, width), width)
                if to > from {
                    context.fill(Path(CGRect(x: from, y: 4, width: to - from, height: baseline - 4)),
                                 with: .color(Theme.spot.opacity(0.14)))
                    let lines = ["SLACK", Self.clock.string(from: slack.start) + "–"
                                 + Self.clock.string(from: slack.end)]
                    for (row, line) in lines.enumerated() {
                        let label = context.resolve(Text(line).font(Theme.micro(7))
                            .foregroundStyle(Theme.spot))
                        let labelWidth = label.measure(in: size).width
                        // Centred on the box, but a narrow box shouldn't push it off the edge.
                        let left = min(max((from + to) / 2 - labelWidth / 2, 2),
                                       width - labelWidth - 2)
                        context.draw(label, at: CGPoint(x: left, y: 4 + CGFloat(row) * 10),
                                     anchor: .topLeading)
                    }
                }
            }

            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: baseline))
                                  $0.addLine(to: CGPoint(x: width, y: baseline)) },
                           with: .color(shifting ? Theme.spot : Theme.ink), lineWidth: 1.2)

            for (time, label) in axisTicks() {
                let tick = x(time, width)
                context.stroke(Path { $0.move(to: CGPoint(x: tick, y: baseline))
                                      $0.addLine(to: CGPoint(x: tick, y: baseline + 4)) },
                               with: .color(Theme.ink), lineWidth: 1)
                context.draw(Text(label).font(Theme.micro(7)).tracking(1.4)
                    .foregroundStyle(Theme.mute),
                             at: CGPoint(x: tick + 4, y: baseline + 6), anchor: .topLeading)
            }

            currentStrip(context, width: width, zero: zero, knot: knot)
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: zero))
                                  $0.addLine(to: CGPoint(x: width, y: zero)) },
                           with: .color(Theme.ink.opacity(0.4)), lineWidth: 0.6)
            for slack in slacks {
                let cx = slackX(slack, width)
                guard cx >= 0, cx <= width else { continue }
                context.stroke(Path { $0.move(to: CGPoint(x: cx - 3.5, y: zero - 3.5))
                                      $0.addLine(to: CGPoint(x: cx + 3.5, y: zero + 3.5))
                                      $0.move(to: CGPoint(x: cx + 3.5, y: zero - 3.5))
                                      $0.addLine(to: CGPoint(x: cx - 3.5, y: zero + 3.5)) },
                               with: .color(.black), lineWidth: 1.4)
            }
            context.draw(Text("FLOOD ABOVE, EBB BELOW").font(Theme.micro(7)).tracking(1.2)
                .foregroundStyle(Theme.mute),
                         at: CGPoint(x: width / 2, y: size.height - 1), anchor: .bottom)

            let marker = x(now, width)
            if !shifting, marker >= 0, marker <= width {
                context.stroke(Path { $0.move(to: CGPoint(x: marker, y: 4))
                                      $0.addLine(to: CGPoint(x: marker, y: baseline)) },
                               with: .color(Theme.ink), lineWidth: 1)
                if let height = Conditions.height(at: now, in: curve) {
                    let y = baseline - CGFloat(normalise(height)) * amplitude
                    context.fill(Path(ellipseIn: CGRect(x: marker - 3.6, y: y - 3.6,
                                                        width: 7.2, height: 7.2)),
                                 with: .color(Theme.ink))
                }
            }
        }
    }

    // MARK: - Geometry

    private func x(_ time: Date, _ width: CGFloat) -> CGFloat {
        let span = window.end.timeIntervalSince(window.start)
        guard span > 0 else { return 0 }
        return CGFloat(time.timeIntervalSince(window.start) / span) * width
    }

    /// The inverse of `x` — a drag location back to a time, clamped to the window.
    private func time(at x: CGFloat, width: CGFloat) -> Date {
        let span = window.end.timeIntervalSince(window.start)
        let fraction = max(0, min(1, width > 0 ? x / width : 0))
        return window.start.addingTimeInterval(span * Double(fraction))
    }

    /// The curve's own range over the whole range on offer, padded, so a neap day still
    /// fills the band. Not the zoomed slice: pinching moves the time axis only.
    private var bounds: (low: Double, high: Double) {
        let visible = curve.filter { $0.time >= fullWindow.start && $0.time <= fullWindow.end }
        let heights = (visible.isEmpty ? curve : visible).map(\.height)
        guard let low = heights.min(), let high = heights.max(), high > low else {
            return (0, 6)
        }
        let pad = (high - low) * 0.08
        return (low - pad, high + pad)
    }

    private func normalise(_ height: Double) -> Double {
        let (low, high) = bounds
        return (height - low) / (high - low)
    }

    /// Returns the stroked curve and the same curve closed to the baseline for filling.
    private func tidePath(width: CGFloat, baseline: CGFloat,
                          amplitude: CGFloat) -> (line: Path, area: Path)? {
        // One sample past each edge, so a zoomed curve runs to the border, not 9pt short.
        let visible = curve.filter {
            $0.time >= window.start.addingTimeInterval(-360)
                && $0.time <= window.end.addingTimeInterval(360)
        }
        guard visible.count > 1 else { return nil }
        var line = Path()
        for (index, sample) in visible.enumerated() {
            let point = CGPoint(x: x(sample.time, width),
                                y: baseline - CGFloat(normalise(sample.height)) * amplitude)
            index == 0 ? line.move(to: point) : line.addLine(to: point)
        }
        var area = line
        area.addLine(to: CGPoint(x: x(visible.last!.time, width), y: baseline))
        area.addLine(to: CGPoint(x: x(visible.first!.time, width), y: baseline))
        area.closeSubpath()
        return (line, area)
    }

    /// A printer's duotone: dots on a 4pt grid, clipped to the water. Cheaper to read
    /// at a glance than a gradient and it survives being 90pt tall. Faint everywhere,
    /// full colour in the columns under a swim window.
    private func halftone(_ context: GraphicsContext, clippedTo area: Path,
                          width: CGFloat, height: CGFloat, focus: [ClosedRange<CGFloat>]) {
        context.drawLayer { layer in
            layer.clip(to: area)
            let full = Theme.spot
            let faded = Theme.spot.opacity(0.15)
            for row in stride(from: CGFloat(1.4), to: height, by: 4) {
                for column in stride(from: CGFloat(1.4), to: width, by: 4) {
                    let dot = focus.contains { $0.contains(column) } ? full : faded
                    layer.fill(Path(ellipseIn: CGRect(x: column - 1.05, y: row - 1.05,
                                                      width: 2.1, height: 2.1)),
                               with: .color(dot))
                }
            }
        }
    }

    /// Flood up in ink, ebb down in blue. Signed, so the reversal reads as a crossing.
    private func currentStrip(_ context: GraphicsContext, width: CGFloat,
                              zero: CGFloat, knot: CGFloat) {
        guard !samples.isEmpty else { return }
        let span = window.end.timeIntervalSince(window.start) / Double(bars)
        let barWidth = width / CGFloat(bars) - 1.3
        for index in 0..<bars {
            let time = window.start.addingTimeInterval(span * (Double(index) + 0.5))
            guard let velocity = Conditions.velocity(at: time, in: samples) else { continue }
            let length = max(CGFloat(abs(velocity)) * knot, 0.7)
            let rect = CGRect(x: CGFloat(index) * (width / CGFloat(bars)),
                              y: velocity > 0 ? zero - length : zero,
                              width: barWidth, height: length)
            context.fill(Path(rect),
                         with: .color((velocity > 0 ? Theme.ink : Theme.spot).opacity(0.74)))
        }
    }

    /// Six-hour marks over a day, midnights over the whole range — the same axis cannot
    /// carry both, and twenty labels at 7pt is a smear. Pinched in, the marks close up
    /// to three hours and then to every hour.
    private func axisTicks() -> [(Date, String)] {
        let span = window.end.timeIntervalSince(window.start)
        let step: TimeInterval = span > 36 * 3600 ? 24 * 3600
            : span > 14 * 3600 ? 6 * 3600 : span > 6 * 3600 ? 3 * 3600 : 3600
        var ticks: [(Date, String)] = []
        var time = Conditions.calendar.startOfDay(for: window.start)
        while time <= window.end {
            defer { time.addTimeInterval(step) }
            guard time >= window.start else { continue }
            if step == 24 * 3600 {
                ticks.append((time, Self.weekday.string(from: time).uppercased()))
            } else {
                ticks.append((time, Self.hourName(Conditions.calendar.component(.hour, from: time))))
            }
        }
        return ticks
    }

    private static func hourName(_ hour: Int) -> String {
        switch hour {
        case 0: "MIDNIGHT"
        case 12: "NOON"
        default: "\(hour % 12) \(hour < 12 ? "AM" : "PM")"
        }
    }

    /// `11:17AM`, for the slack box.
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "h:mma"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
