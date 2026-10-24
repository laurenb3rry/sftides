import SwiftUI

/// The tide curve is the shape of the day, with each of the current's slacks marked on it by
/// a ring and a dashed line rising to its time. Drawn as a figure rather than a chart: no boxed plot area, no legend,
/// a halftone fill instead of a gradient.
struct TideFigure: View {
    let curve: [TideSample]
    let samples: [CurrentSample]
    /// Only the moment of each is drawn; the table carries the windows.
    let slacks: [SlackWindow]
    /// Every west or east swim window in range, from its first start to its last finish.
    /// Under them the halftone dots give way to arrows, pointing the way the route goes.
    let swims: [(range: ClosedRange<Date>, east: Bool)]
    /// The whole range on offer. A day of it is shown at a time, 6 AM to 8 PM; pinching
    /// narrows that and dragging the axis moves it, but never past those edges.
    let fullWindow: (start: Date, end: Date)
    /// The day on show, as an offset from the start of `fullWindow`. Set from outside to
    /// snap the view to that whole day.
    @Binding var day: Int
    /// Where the dot and the vertical tick are drawn — real "now" until the figure is
    /// scrubbed, then wherever the finger last was.
    let now: Date
    /// Fires with the time under the finger as the figure is dragged, so the caller
    /// can move the marker and update the strip above without the figure owning state.
    var onScrub: ((Date) -> Void)?

    /// Vertical layout, measured up from the bottom of the plot: room for the axis labels,
    /// and the curve takes everything above.
    private let axisHeight: CGFloat = 18
    /// Where the slack lines and the marker start. The curve's peak sits `peak` down,
    /// so there is a little headroom over it.
    private let top: CGFloat = 14
    private let peak: CGFloat = 28
    /// Under the 26pt page margin, so the widest label stays on screen.
    private let overflow: CGFloat = 24

    /// Four hours is as far in as the 6-minute data stays worth reading.
    private let minZoomSpan: TimeInterval = 4 * 3600

    @State private var zoomSpan: TimeInterval?
    /// Nil sits on the start of `day`.
    @State private var zoomStart: Date?
    /// The shown window when the current pinch began, so the whole pinch is measured
    /// against it rather than compounding frame to frame.
    @State private var pinch: (start: Date, span: TimeInterval)?
    @State private var pinching = false
    /// Tapping the axis hands the finger to the time range: drags shift it, and the
    /// marker is hidden because nothing is being read off the curve. A tap anywhere
    /// on the figure hands it back.
    @State private var shifting = false
    @State private var panBase: Date?

    /// The hours a day is shown for: no one swims before 6 AM or after 8 PM.
    private let dayFirstHour = 6
    private let daySpan: TimeInterval = 14 * 3600

    private func dayStart(_ offset: Int) -> Date {
        let midnight = Conditions.calendar.date(byAdding: .day, value: offset, to: fullWindow.start)!
        return midnight.addingTimeInterval(TimeInterval(dayFirstHour) * 3600)
    }

    /// Keeps a window of `span` inside the day on show, 6 AM to 8 PM: a hard edge, so
    /// neither pinching nor dragging the axis can show the night or the next day. Other
    /// days come from the stepper.
    private func clamped(_ start: Date, span: TimeInterval) -> Date {
        let first = dayStart(day)
        return min(max(start, first), first.addingTimeInterval(daySpan - span))
    }

    /// What is on screen: a day, or the pinched-in slice of one. Everything below reads
    /// this, so scrubbing and drawing stay in step with the zoom.
    private var window: (start: Date, end: Date) {
        let span = zoomSpan ?? daySpan
        let start = clamped(zoomStart ?? dayStart(day), span: span)
        return (start, start.addingTimeInterval(span))
    }

    /// The day under the middle of the screen, so the stepper names what is mostly shown.
    private var middleDay: Int {
        let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start) / 2)
        let offset = Conditions.calendar.dateComponents(
            [.day], from: fullWindow.start, to: Conditions.calendar.startOfDay(for: middle)).day ?? 0
        return min(max(offset, 0), 3)
    }

    private func syncDay() { day = middleDay }

    var body: some View {
        GeometryReader { geometry in
            // The canvas runs `overflow` wider than the figure each side, so an axis label
            // centred on an end tick has room; the frame the gestures read stays the figure's.
            ZStack {
                canvas
                    .frame(width: geometry.size.width + 2 * overflow, height: geometry.size.height)
            }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Two fingers are a pinch, not a scrub.
                        guard !pinching else { return }
                        if shifting {
                            pan(by: value.translation.width, width: geometry.size.width)
                            return
                        }
                        // A touch that starts on the axis is a tap on it, not a scrub.
                        guard !onAxis(value.startLocation, in: geometry.size) else { return }
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
                        }
                    })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged(zoom)
                    .onEnded { _ in
                        pinch = nil
                        pinching = false
                    })
        }
        // A day picked from outside shows whole; one the drag just landed on is left as is.
        .onChange(of: day) {
            guard day != middleDay else { return }
            zoomSpan = nil
            zoomStart = nil
            shifting = false
        }
    }

    /// Keeps the time under the fingers where it started, so the pinch zooms into the
    /// spot it was made over rather than toward the middle.
    private func zoom(_ value: MagnifyGesture.Value) {
        pinching = true
        if pinch == nil { pinch = (window.start, window.end.timeIntervalSince(window.start)) }
        guard let base = pinch else { return }
        let span = min(max(base.span / value.magnification, minZoomSpan), daySpan)
        let anchor = base.start.addingTimeInterval(base.span * value.startAnchor.x)
        zoomSpan = span
        zoomStart = anchor.addingTimeInterval(-span * value.startAnchor.x)
        syncDay()
    }

    /// The time axis: the rule and the labels hanging under it.
    private func onAxis(_ point: CGPoint, in size: CGSize) -> Bool {
        let baseline = rows(size.height).baseline
        return point.y > baseline - 6 && point.y < baseline + 20
    }

    /// Drags the zoomed window, finger-with-the-chart: dragging right shows earlier times.
    /// Measured from where the drag began, and clamped to the range on offer.
    private func pan(by translation: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let span = zoomSpan ?? daySpan
        if panBase == nil { panBase = window.start }
        guard let base = panBase else { return }
        zoomStart = clamped(base.addingTimeInterval(-span * Double(translation / width)),
                            span: span)
        syncDay()
    }

    /// The baseline leaves room under it for the axis labels; the curve fills the rest.
    private func rows(_ height: CGFloat) -> (baseline: CGFloat, amplitude: CGFloat) {
        let baseline = height - axisHeight
        return (baseline, baseline - peak)
    }

    private var canvas: some View {
        Canvas { context, size in
            let width = size.width - 2 * overflow
            context.translateBy(x: overflow, y: 0)
            let (baseline, amplitude) = rows(size.height)

            for step in 1..<3 {
                let y = peak + (baseline - peak) * CGFloat(step) / 3
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y))
                                      $0.addLine(to: CGPoint(x: width, y: y)) },
                               with: .color(Theme.faint), lineWidth: 0.6)
            }

            if let (line, area) = tidePath(width: width, baseline: baseline,
                                           amplitude: amplitude) {
                let focus = swims.map { (x($0.range.lowerBound, width)...x($0.range.upperBound, width), $0.east) }
                halftone(context, clippedTo: area, width: width, height: baseline, focus: focus)
                context.stroke(line, with: .color(Theme.ink), lineWidth: 1.7)
            }

            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: baseline))
                                  $0.addLine(to: CGPoint(x: width, y: baseline)) },
                           with: .color(shifting ? Theme.spot : Theme.ink), lineWidth: 1.2)

            // A slack is an instant: a ring on the curve (the filled dot stays "now") and a
            // dashed line from it up to the time. Only upward; below the curve is the water.
            for slack in slacks {
                let mark = x(slack.time, width)
                guard mark >= 0, mark <= width,
                      let height = Conditions.height(at: slack.time, in: curve) else { continue }
                let y = baseline - CGFloat(normalise(height)) * amplitude
                context.stroke(Path { $0.move(to: CGPoint(x: mark, y: y - 3.2))
                                      $0.addLine(to: CGPoint(x: mark, y: top)) },
                               with: .color(Theme.spot),
                               style: StrokeStyle(lineWidth: 0.9, dash: [2, 2.2]))
                let ring = CGRect(x: mark - 3.2, y: y - 3.2, width: 6.4, height: 6.4)
                context.fill(Path(ellipseIn: ring), with: .color(Theme.paper))
                context.stroke(Path(ellipseIn: ring), with: .color(Theme.ink), lineWidth: 1.1)
                let text = context.resolve(
                    Text("SLACK " + Self.hourName(Conditions.calendar.component(.hour, from: slack.time),
                                                  Conditions.calendar.component(.minute, from: slack.time)))
                        .font(Theme.micro(6)).tracking(1.2).foregroundStyle(Theme.mute))
                // Pulled in rather than run off the screen, as the axis labels are.
                let half = text.measure(in: size).width / 2
                let centre = min(max(mark, half - overflow + 2), width + overflow - half - 2)
                context.draw(text, at: CGPoint(x: centre, y: top - 4), anchor: .bottom)
            }

            let ticks = axisTicks()
            for (time, name) in ticks {
                let tick = x(time, width)
                context.stroke(Path { $0.move(to: CGPoint(x: tick, y: baseline))
                                      $0.addLine(to: CGPoint(x: tick, y: baseline + 4)) },
                               with: .color(Theme.ink), lineWidth: 1)
                let text = context.resolve(Text(name).font(Theme.micro(7)).tracking(1.4)
                    .foregroundStyle(Theme.mute))
                // Centred under its tick; an end label is pulled back rather than run off
                // the screen.
                let half = text.measure(in: size).width / 2
                let centre = min(max(tick, half - overflow + 2), width + overflow - half - 2)
                context.draw(text, at: CGPoint(x: centre, y: baseline + 6), anchor: .top)
            }

            let marker = x(now, width)
            if !shifting, marker >= 0, marker <= width {
                context.stroke(Path { $0.move(to: CGPoint(x: marker, y: top))
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

    /// A printer's duotone: dots on a 6pt grid, clipped to the water. Cheaper to read
    /// at a glance than a gradient and it survives being 90pt tall. Faint dots everywhere;
    /// under a swim window each dot becomes a tiny arrow, right for east and left for west.
    /// Where a west and an east window overlap the two alternate by row.
    private func halftone(_ context: GraphicsContext, clippedTo area: Path,
                          width: CGFloat, height: CGFloat,
                          focus: [(span: ClosedRange<CGFloat>, east: Bool)]) {
        context.drawLayer { layer in
            layer.clip(to: area)
            let faded = Theme.spot.opacity(0.15)
            // Centres on half-points, so a pixel boundary falls mid-glyph at 2x and 3x and the
            // left and right arrows rasterise as mirror images.
            for (index, row) in stride(from: CGFloat(3), to: height, by: 6).enumerated() {
                for column in stride(from: CGFloat(3), to: width, by: 6) {
                    let under = focus.filter { $0.span.contains(column) }.map(\.east)
                    let east = Set(under).count == 2 ? index.isMultiple(of: 2) : under.first
                    guard let east else {
                        layer.fill(Path(ellipseIn: CGRect(x: column - 1.2, y: row - 1.2,
                                                          width: 2.4, height: 2.4)),
                                   with: .color(faded))
                        continue
                    }
                    layer.fill(Self.arrow(at: CGPoint(x: column, y: row), east: east),
                               with: .color(Theme.spot))
                }
            }
        }
    }

    /// 4.2pt wide: a shaft and a solid triangular head, mirrored exactly for west.
    private static func arrow(at centre: CGPoint, east: Bool) -> Path {
        let sign: CGFloat = east ? 1 : -1
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + sign * dx, y: centre.y + dy)
        }
        var path = Path()
        path.move(to: point(-2.1, -0.4))
        path.addLine(to: point(0.3, -0.4))
        path.addLine(to: point(0.3, -1.5))
        path.addLine(to: point(2.1, 0))
        path.addLine(to: point(0.3, 1.5))
        path.addLine(to: point(0.3, 0.4))
        path.addLine(to: point(-2.1, 0.4))
        path.closeSubpath()
        return path
    }

    /// Five marks over a day, 3½ hours apart from 6 AM to 8 PM. Pinched in, the marks
    /// close up to every hour.
    private func axisTicks() -> [(Date, String)] {
        let span = window.end.timeIntervalSince(window.start)
        let step: TimeInterval = span > 6 * 3600 ? 3.5 * 3600 : 3600
        var ticks: [(Date, String)] = []
        var time = Conditions.calendar.startOfDay(for: window.start)
        // The 3½-hour marks are counted from 6 AM, which is not a multiple of the step.
        if span > 6 * 3600 { time.addTimeInterval(TimeInterval(dayFirstHour) * 3600 - 3 * step) }
        while time <= window.end {
            defer { time.addTimeInterval(step) }
            guard time >= window.start else { continue }
            ticks.append((time, Self.hourName(Conditions.calendar.component(.hour, from: time),
                                              Conditions.calendar.component(.minute, from: time))))
        }
        return ticks
    }

    private static func hourName(_ hour: Int, _ minute: Int) -> String {
        let clock = minute == 0 ? "\(hour % 12 == 0 ? 12 : hour % 12)"
            : "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))"
        return clock + (hour < 12 ? "AM" : "PM")
    }
}
