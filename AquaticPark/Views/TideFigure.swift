import SwiftUI

/// The tide curve is the shape of the day; two toggles under the axis lay what the Gate
/// is doing inside that shape on top of it — slack windows, and flood and ebb as areas
/// under the curve. Drawn as a figure rather than a chart: no boxed plot area, no legend,
/// a halftone fill instead of a gradient.
struct TideFigure: View {
    let curve: [TideSample]
    let samples: [CurrentSample]
    /// Shaded and labelled with their span when the slack toggle is on.
    let slacks: [SlackWindow]
    /// Every west or east swim window in range. Under them the halftone dots give way to
    /// arrows, pointing the way the route goes.
    let swims: [(range: ClosedRange<Date>, east: Bool)]
    /// The whole range on offer. A day of it is shown at a time; pinching narrows that
    /// and dragging the axis moves it, across midnight into the next day.
    let fullWindow: (start: Date, end: Date)
    /// The day on show, as an offset from the start of `fullWindow`. Follows the axis
    /// as it is dragged; setting it from outside snaps the view to that whole day.
    @Binding var day: Int
    /// Where the dot and the vertical tick are drawn — real "now" until the figure is
    /// scrubbed, then wherever the finger last was.
    let now: Date
    /// Fires with the time under the finger as the figure is dragged, so the caller
    /// can move the marker and update the strip above without the figure owning state.
    var onScrub: ((Date) -> Void)?

    /// Vertical layout, measured up from the bottom of the plot: room for the axis labels,
    /// and the curve takes everything above. The toggle row sits under the plot.
    private let axisHeight: CGFloat = 18
    private let toggleHeight: CGFloat = 22
    /// Under the 26pt page margin, so the widest label stays on screen.
    private let overflow: CGFloat = 24

    /// Four hours is as far in as the 6-minute data stays worth reading.
    private let minZoomSpan: TimeInterval = 4 * 3600

    @State private var showSlack = false
    @State private var showCurrents = false
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

    private let daySpan: TimeInterval = 24 * 3600

    private func startOfDay(_ offset: Int) -> Date {
        Conditions.calendar.date(byAdding: .day, value: offset, to: fullWindow.start)!
    }

    /// What is on screen: a day, or the pinched-in slice of one. Everything below reads
    /// this, so scrubbing and drawing stay in step with the zoom.
    private var window: (start: Date, end: Date) {
        let span = zoomSpan ?? daySpan
        let start = min(max(zoomStart ?? startOfDay(day), fullWindow.start),
                        fullWindow.end.addingTimeInterval(-span))
        return (start, start.addingTimeInterval(span))
    }

    /// The day under the middle of the screen, so the toggle names what is mostly shown.
    private var middleDay: Int {
        let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start) / 2)
        let offset = Conditions.calendar.dateComponents(
            [.day], from: fullWindow.start, to: Conditions.calendar.startOfDay(for: middle)).day ?? 0
        return min(max(offset, 0), 3)
    }

    private func syncDay() { day = middleDay }

    var body: some View {
        VStack(spacing: 0) {
            plot
            HStack(spacing: 20) {
                toggle("SLACK", isOn: $showSlack)
                toggle("CURRENTS", isOn: $showCurrents)
                Spacer()
            }
            .frame(height: toggleHeight)
        }
    }

    /// An ink box, filled and ticked in paper when on — a printed form's checkbox.
    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(Theme.ink, lineWidth: 1)
                    .background(isOn.wrappedValue ? Theme.ink : .clear)
                    .overlay {
                        if isOn.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6.5, weight: .heavy))
                                .foregroundStyle(Theme.paper)
                        }
                    }
                    .frame(width: 10, height: 10)
                MicroLabel(text: label, tracking: 1.29,
                           color: isOn.wrappedValue ? Theme.ink : Theme.mute)
            }
            // Grows the hit area without growing the row.
            .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
    }

    private var plot: some View {
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
        let latest = fullWindow.end.addingTimeInterval(-span)
        let start = base.addingTimeInterval(-span * Double(translation / width))
        zoomStart = min(max(start, fullWindow.start), latest)
        syncDay()
    }

    /// The baseline leaves room under it for the axis labels; the curve fills the rest.
    private func rows(_ height: CGFloat) -> (baseline: CGFloat, amplitude: CGFloat) {
        let baseline = height - axisHeight
        // The curve tops out 28pt down, below the two lines of the slack label.
        return (baseline, baseline - 28)
    }

    private var canvas: some View {
        Canvas { context, size in
            let width = size.width - 2 * overflow
            context.translateBy(x: overflow, y: 0)
            let (baseline, amplitude) = rows(size.height)

            for step in 1..<3 {
                let y = 28 + (baseline - 28) * CGFloat(step) / 3
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y))
                                      $0.addLine(to: CGPoint(x: width, y: y)) },
                               with: .color(Theme.faint), lineWidth: 0.6)
            }

            if let (line, area) = tidePath(width: width, baseline: baseline,
                                           amplitude: amplitude) {
                let focus = swims.map { (x($0.range.lowerBound, width)...x($0.range.upperBound, width), $0.east) }
                halftone(context, clippedTo: area, width: width, height: baseline, focus: focus)
                context.stroke(line, with: .color(Theme.ink), lineWidth: 1.7)

                if showCurrents {
                    let periods = currentPeriods()
                    for (period, phase) in zip(periods, hatchPhases(periods, width: width)) {
                        currentArea(context, period, phase: phase, area: area, size: size,
                                    width: width, baseline: baseline, amplitude: amplitude)
                    }
                }
            }

            if showSlack {
                var reached = -CGFloat.infinity
                for slack in slacks {
                    let from = max(x(slack.start, width), 0)
                    let to = min(x(slack.end, width), width)
                    guard to > from else { continue }
                    context.fill(Path(CGRect(x: from, y: 4, width: to - from, height: baseline - 4)),
                                 with: .color(Theme.spot.opacity(0.14)))

                    let lines = ["SLACK", Self.clock.string(from: slack.start) + "–"
                                 + Self.clock.string(from: slack.end)]
                    let labels = lines.map {
                        context.resolve(Text($0).font(Theme.micro(7)).foregroundStyle(Theme.spot))
                    }
                    // Centred on the whole window, never nudged: a label that would run off
                    // the graph or touch the one before it is left off.
                    let centre = (x(slack.start, width) + x(slack.end, width)) / 2
                    let half = (labels.map { $0.measure(in: size).width }.max() ?? 0) / 2
                    guard centre - half >= 0, centre + half <= width,
                          centre - half > reached + 4 else { continue }
                    reached = centre + half
                    for (row, label) in labels.enumerated() {
                        context.draw(label, at: CGPoint(x: centre, y: 4 + CGFloat(row) * 10),
                                     anchor: .top)
                    }
                }
            }

            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: baseline))
                                  $0.addLine(to: CGPoint(x: width, y: baseline)) },
                           with: .color(shifting ? Theme.spot : Theme.ink), lineWidth: 1.2)

            let ticks = axisTicks()
            for (time, name) in ticks {
                // Dragged off a whole day, a midnight on the axis says which day it begins.
                let wholeDay = window.start == Conditions.calendar.startOfDay(for: window.start)
                    && window.end.timeIntervalSince(window.start) >= daySpan
                let dayed = !wholeDay && time == Conditions.calendar.startOfDay(for: time)
                let label = dayed ? Self.weekday.string(from: time).uppercased() + " " + name : name
                let tick = x(time, width)
                context.stroke(Path { $0.move(to: CGPoint(x: tick, y: baseline))
                                      $0.addLine(to: CGPoint(x: tick, y: baseline + 4)) },
                               with: .color(Theme.ink), lineWidth: 1)
                let text = context.resolve(Text(label).font(Theme.micro(7)).tracking(1.4)
                    .foregroundStyle(Theme.mute))
                // Centred under its tick; an end label is pulled back rather than run off
                // the screen.
                let half = text.measure(in: size).width / 2
                let centre = min(max(tick, half - overflow + 2), width + overflow - half - 2)
                context.draw(text, at: CGPoint(x: centre, y: baseline + 6), anchor: .top)
            }

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
                    let east = under.count == 2 ? index.isMultiple(of: 2) : under.first
                    guard let east else {
                        // The hatching stands in for the faint dots; only arrows stay.
                        if showCurrents { continue }
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

    /// Each run of the Gate in one direction, split where the velocity crosses zero
    /// (interpolated between the 6-minute samples, as `Conditions.velocity` is).
    private func currentPeriods() -> [(start: Date, end: Date, flood: Bool)] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var periods: [(start: Date, end: Date, flood: Bool)] = []
        var start = first.time
        var flood = first.velocity > 0
        for (a, b) in zip(samples, samples.dropFirst()) where (b.velocity > 0) != flood {
            let crossing = a.time.addingTimeInterval(
                b.time.timeIntervalSince(a.time) * a.velocity / (a.velocity - b.velocity))
            periods.append((start, crossing, flood))
            start = crossing
            flood.toggle()
        }
        periods.append((start, last.time, flood))
        return periods
    }

    /// Where each period's hatching sits along the axis, chosen so the lines of one period
    /// meet the lines of the next exactly on the boundary between them. A `/` and a `\`
    /// meet there when their phases mirror about the boundary: next = 2 * boundary - this.
    /// Walked from the first period, so it holds however the graph is zoomed or dragged.
    private func hatchPhases(_ periods: [(start: Date, end: Date, flood: Bool)],
                             width: CGFloat) -> [CGFloat] {
        guard let first = periods.first else { return [] }
        var phases = [x(first.start, width)]
        for period in periods.dropFirst() {
            phases.append(2 * x(period.start, width) - phases.last!)
        }
        return phases
    }

    /// The area under the curve for one flood or ebb, hatched in ink with its name and span
    /// in the middle of the whole period (not of what is on screen), on a paper-coloured
    /// patch so the hatching does not run through the type.
    private func currentArea(_ context: GraphicsContext,
                             _ period: (start: Date, end: Date, flood: Bool), phase: CGFloat,
                             area: Path, size: CGSize,
                             width: CGFloat, baseline: CGFloat, amplitude: CGFloat) {
        let fullFrom = x(period.start, width)
        let fullTo = x(period.end, width)
        let from = max(fullFrom, 0)
        let to = min(fullTo, width)
        guard to > from else { return }

        // Hatched in ink, the two directions opposed: flood leans / and ebb leans \.
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: from, y: 0, width: to - from, height: baseline)))
            layer.clip(to: area)
            let pitch: CGFloat = 5 * 2.0.squareRoot()
            var hatch = Path()
            var cx = phase + pitch * ((from - baseline - phase) / pitch).rounded(.down)
            while cx < to + baseline {
                hatch.move(to: CGPoint(x: cx, y: baseline))
                hatch.addLine(to: CGPoint(x: cx + (period.flood ? baseline : -baseline), y: 0))
                cx += pitch
            }
            layer.stroke(hatch, with: .color(Theme.ink.opacity(0.2)), lineWidth: 0.9)
        }

        let span = Self.clock.string(from: period.start) + "–" + Self.clock.string(from: period.end)
        let title = context.resolve(Text(period.flood ? "FLOOD" : "EBB")
            .font(Theme.micro(7)).foregroundStyle(Theme.ink))
        let times = context.resolve(Text(span).font(Theme.micro(7)).foregroundStyle(Theme.ink))
        let labelWidth = max(times.measure(in: size).width, title.measure(in: size).width)
        let patch = labelWidth + 8
        // Tied to the middle of the whole period, so it moves with the area and nowhere else.
        // Left off when it would spill out of the period or off the graph, or when the curve
        // comes down into it — the colours alone carry a four-day view.
        let mid = (fullFrom + fullTo) / 2
        guard patch < fullTo - fullFrom, mid - patch / 2 >= 0, mid + patch / 2 <= width
        else { return }
        let top = baseline - 22
        let clear = stride(from: -1.0, through: 1.0, by: 0.25).allSatisfy { step in
            let at = mid + CGFloat(step) * patch / 2
            guard let height = Conditions.height(at: time(at: at, width: width), in: curve)
            else { return false }
            return baseline - CGFloat(normalise(height)) * amplitude < top - 3
        }
        guard clear else { return }
        // A patch hugging each line of type, as on a story caption, not one box.
        for (label, y) in [(title, baseline - 16), (times, baseline - 7)] {
            let box = label.measure(in: size)
            context.fill(Path(roundedRect: CGRect(x: mid - box.width / 2 - 3, y: y - box.height / 2 - 1,
                                                  width: box.width + 6, height: box.height + 2),
                              cornerRadius: 3),
                         with: .color(Theme.paper))
        }
        context.draw(title, at: CGPoint(x: mid, y: baseline - 16), anchor: .center)
        context.draw(times, at: CGPoint(x: mid, y: baseline - 7), anchor: .center)
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
        default: "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "AM" : "PM")"
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
