import SwiftUI

/// Tide above, current below, on one shared 24-hour axis — the pairing is the point.
/// The tide curve is the shape of the day; the bars under it are what the Gate is doing
/// inside that shape, and swimmers care about the second one. Drawn as a figure rather
/// than a chart: no boxed plot area, no legend, a halftone fill instead of a gradient.
struct TideFigure: View {
    let curve: [TideSample]
    let samples: [CurrentSample]
    let window: (start: Date, end: Date)
    /// Shaded and labelled, so the headline time span has a place on the axis.
    let highlight: SwimWindow?
    let highlightLabel: String
    /// Where the dot and the vertical tick are drawn — real "now" until the figure is
    /// scrubbed, then wherever the finger last was.
    let now: Date
    /// Fires with the time under the finger as the figure is dragged, so the caller
    /// can move the marker and update the strip above without the figure owning state.
    var onScrub: ((Date) -> Void)?

    /// Vertical layout as fractions of whatever height the figure is handed, taken from
    /// the approved 170pt mockup so the proportions survive on a shorter screen.
    private let baselineFraction: CGFloat = 0.541
    private let amplitudeFraction: CGFloat = 0.482
    private let zeroFraction: CGFloat = 0.788
    private let knotFraction: CGFloat = 0.0506

    /// The current strip reads as texture, not as 240 separate readings.
    private let bars = 72

    var body: some View {
        GeometryReader { geometry in
            canvas
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    onScrub?(time(at: value.location.x, width: geometry.size.width))
                })
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            let width = size.width
            let baseline = size.height * baselineFraction
            let amplitude = size.height * amplitudeFraction
            let zero = size.height * zeroFraction

            for step in 1..<3 {
                let y = 10 + (baseline - 10) * CGFloat(step) / 3
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y))
                                      $0.addLine(to: CGPoint(x: width, y: y)) },
                               with: .color(Theme.faint), lineWidth: 0.6)
            }

            if let (line, area) = tidePath(width: width, baseline: baseline,
                                           amplitude: amplitude) {
                halftone(context, clippedTo: area, width: width, height: baseline)
                context.stroke(line, with: .color(Theme.ink), lineWidth: 1.7)
            }

            if let highlight {
                let from = x(highlight.start, width)
                let to = x(highlight.end, width)
                if to > 0, from < width {
                    let band = CGRect(x: max(from, 0), y: 4,
                                      width: min(to, width) - max(from, 0), height: baseline - 4)
                    context.fill(Path(band), with: .color(Theme.spot.opacity(0.14)))
                    context.draw(Text(highlightLabel).font(Theme.micro(7))
                        .foregroundStyle(Theme.spot),
                                 at: CGPoint(x: band.minX + 3, y: 4), anchor: .topLeading)
                }
            }

            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: baseline))
                                  $0.addLine(to: CGPoint(x: width, y: baseline)) },
                           with: .color(Theme.ink), lineWidth: 1.2)

            for (time, label) in axisTicks() {
                let tick = x(time, width)
                context.stroke(Path { $0.move(to: CGPoint(x: tick, y: baseline))
                                      $0.addLine(to: CGPoint(x: tick, y: baseline + 4)) },
                               with: .color(Theme.ink), lineWidth: 1)
                context.draw(Text(label).font(Theme.micro(7)).tracking(1.4)
                    .foregroundStyle(Theme.mute),
                             at: CGPoint(x: tick + 4, y: baseline + 6), anchor: .topLeading)
            }

            currentStrip(context, width: width, zero: zero,
                         knot: size.height * knotFraction)
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: zero))
                                  $0.addLine(to: CGPoint(x: width, y: zero)) },
                           with: .color(Theme.ink.opacity(0.4)), lineWidth: 0.6)
            context.draw(Text("FLOOD ABOVE, EBB BELOW").font(Theme.micro(7)).tracking(1.2)
                .foregroundStyle(Theme.mute),
                         at: CGPoint(x: width / 2, y: size.height - 1), anchor: .bottom)

            let marker = x(now, width)
            if marker >= 0, marker <= width {
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

    /// The curve's own range, padded, so a neap day still fills the band.
    private var bounds: (low: Double, high: Double) {
        let visible = curve.filter { $0.time >= window.start && $0.time <= window.end }
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
        let visible = curve.filter { $0.time >= window.start && $0.time <= window.end }
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
    /// at a glance than a gradient and it survives being 90pt tall.
    private func halftone(_ context: GraphicsContext, clippedTo area: Path,
                          width: CGFloat, height: CGFloat) {
        context.drawLayer { layer in
            layer.clip(to: area)
            let dot = Theme.spot.opacity(0.6)
            for row in stride(from: CGFloat(1.4), to: height, by: 4) {
                for column in stride(from: CGFloat(1.4), to: width, by: 4) {
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
    /// carry both, and twenty labels at 7pt is a smear.
    private func axisTicks() -> [(Date, String)] {
        let span = window.end.timeIntervalSince(window.start)
        let names = [0: "MIDNIGHT", 6: "6 AM", 12: "NOON", 18: "6 PM"]
        let step: TimeInterval = span > 36 * 3600 ? 24 * 3600 : 6 * 3600
        var ticks: [(Date, String)] = []
        var time = Conditions.calendar.startOfDay(for: window.start)
        while time <= window.end {
            defer { time.addTimeInterval(step) }
            guard time >= window.start else { continue }
            if step == 24 * 3600 {
                ticks.append((time, Self.weekday.string(from: time).uppercased()))
            } else if let name = names[Conditions.calendar.component(.hour, from: time)] {
                ticks.append((time, name))
            }
        }
        return ticks
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
