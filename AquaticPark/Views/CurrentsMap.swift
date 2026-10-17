import SwiftUI

/// The central bay, Golden Gate to Bay Bridge, with the water drawn moving through it.
/// Ink weight is speed: on a hard flood or ebb the strokes are dark and heavy, and at
/// slack the paper goes nearly blank, which is the moment worth swimming. Driven by the
/// Gate's own current at whatever time the sheet is reading, so scrubbing the tide
/// figure runs the bay along with it.
struct CurrentsMap: View {
    /// Signed knots at the Gate from `Conditions.velocity`, + flood. Nil holds the water still.
    let knots: Double?
    /// Today's water temperature low and high, for the ends of the key. Nil leaves the key off.
    let water: (low: Double, high: Double)?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow = Flow()

    var body: some View {
        GeometryReader { geometry in
            let frame = Bay.Frame(size: geometry.size)
            ZStack {
                TimelineView(.animation(minimumInterval: 1 / 30,
                                        paused: scenePhase != .active || reduceMotion)) { timeline in
                    Canvas { context, _ in
                        _ = timeline.date
                        flow.step(in: frame, drive: drive)
                        flow.draw(in: &context)
                    }
                }
                // Static, so the halftone is drawn once per size rather than every frame.
                Canvas { context, _ in Bay.drawLand(in: &context, frame: frame, water: water) }
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Currents in the central bay")
    }

    /// The Gate's speed as a fraction of a strong tide; the sign carries flood or ebb.
    private var drive: Double { max(-1.2, min(1.2, (knots ?? 0) / 2.5)) }
}

/// The particles. A reference type held in `@State` so stepping it from the canvas
/// doesn't invalidate the view every frame.
private final class Flow {
    private struct Particle {
        var lon = 0.0, lat = 0.0
        var age = 0, life = 0
        var speed = 0.0
        var trail: [CGPoint] = []
    }

    private var particles: [Particle] = []
    private var frame: Bay.Frame?
    private static let trailLength = 8

    /// Three weights per hue (`Bay.hues`) for slow, moving and fast.
    private static let alphas: [Double] = [0.3, 0.6, 0.9]
    private static let widths: [CGFloat] = [0.6, 0.85, 1.2]

    func step(in frame: Bay.Frame, drive: Double) {
        if frame != self.frame { reset(frame, drive: drive) }
        advance(frame, drive: drive)
    }

    func draw(in context: inout GraphicsContext) {
        var paths = Array(repeating: Path(), count: Bay.hues.count * 3)
        for particle in particles where particle.trail.count > 1 {
            let bucket = Bay.hue(particle.lon, particle.lat) * 3 + min(2, Int(particle.speed * 3))
            paths[bucket].addLines(particle.trail)
        }
        for (index, path) in paths.enumerated() {
            context.stroke(path, with: .color(Bay.hues[index / 3].opacity(Self.alphas[index % 3])),
                           style: StrokeStyle(lineWidth: Self.widths[index % 3], lineCap: .round,
                                              lineJoin: .round))
        }
    }

    /// New size, new particles — and enough steps that the first frame already has trails.
    private func reset(_ frame: Bay.Frame, drive: Double) {
        self.frame = frame
        let count = Int(frame.size.width * frame.size.height / 80)
        particles = (0..<count).map { _ in
            var particle = Particle()
            spawn(&particle, in: frame)
            particle.age = Int.random(in: 0...max(particle.life, 1))
            return particle
        }
        for _ in 0..<Self.trailLength { advance(frame, drive: drive) }
    }

    private func advance(_ frame: Bay.Frame, drive: Double) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        let reach = 2.4 / frame.scale, jitter = 0.3 / frame.scale
        for index in particles.indices {
            var particle = particles[index]
            particle.age += 1
            let (fx, fy) = Bay.flow(particle.lon, particle.lat)
            let ux = fx * drive, uy = fy * drive
            let lon = particle.lon + (ux * reach + .random(in: -0.5...0.5) * jitter) / Bay.kx
            let lat = particle.lat + uy * reach + .random(in: -0.5...0.5) * jitter
            let point = frame.point(lon, lat)
            if particle.age > particle.life || Bay.isLand(lon, lat) || !bounds.contains(point) {
                spawn(&particle, in: frame)
            } else {
                particle.lon = lon
                particle.lat = lat
                particle.speed = min(1, hypot(ux, uy) / 1.25)
                particle.trail.append(point)
                if particle.trail.count > Self.trailLength { particle.trail.removeFirst() }
            }
            particles[index] = particle
        }
    }

    /// Somewhere in the water. A few misses on land are fine; it tries again next frame.
    private func spawn(_ particle: inout Particle, in frame: Bay.Frame) {
        particle.age = 0
        particle.life = 0
        particle.trail = []
        for _ in 0..<14 {
            let point = CGPoint(x: .random(in: 0..<frame.size.width),
                                y: .random(in: 0..<frame.size.height))
            let (lon, lat) = frame.coordinate(point)
            if !Bay.isLand(lon, lat) {
                (particle.lon, particle.lat) = (lon, lat)
                particle.life = .random(in: 40...140)
                particle.trail = [point]
                return
            }
        }
    }
}

/// Hand-traced geography and a sketched flood field. Coordinates are (longitude, latitude).
private enum Bay {
    /// Palette C from the v7 mockups: cool at the Gate, warming into the bay, re-inked
    /// dark enough to read on paper. The particles and the key share it.
    static let hues: [Color] = ([0x1D3B8F, 0x1F6F96, 0x1C8A77, 0xC98A0B, 0xC0391B] as [UInt32])
        .map { Color(hex: $0) }

    /// Shrinks a degree of longitude to the length of a degree of latitude at this latitude.
    static let kx = cos(37.83 * .pi / 180)

    /// The visible window: fixed centre and width, so a taller band shows more north and
    /// south rather than zooming.
    struct Frame: Equatable {
        let size: CGSize
        private static let centre = (lon: -122.432, lat: 37.832)
        private static let span = 0.155

        /// Points per degree of latitude.
        var scale: Double { size.width / (Self.span * Bay.kx) }

        func point(_ lon: Double, _ lat: Double) -> CGPoint {
            CGPoint(x: (lon - Self.centre.lon) * Bay.kx * scale + size.width / 2,
                    y: (Self.centre.lat - lat) * scale + size.height / 2)
        }

        func coordinate(_ point: CGPoint) -> (Double, Double) {
            (Self.centre.lon + (point.x - size.width / 2) / (Bay.kx * scale),
             Self.centre.lat - (point.y - size.height / 2) / scale)
        }
    }

    // MARK: - Shoreline

    static let land: [[(Double, Double)]] = [
        // San Francisco, Lands End round to the Bay Bridge
        [(-122.53, 37.765), (-122.513, 37.775), (-122.512, 37.781), (-122.506, 37.787), (-122.499, 37.788),
         (-122.492, 37.787), (-122.486, 37.79), (-122.483, 37.797), (-122.479, 37.805), (-122.4775, 37.8105),
         (-122.471, 37.8075), (-122.462, 37.805), (-122.452, 37.8055), (-122.444, 37.8065), (-122.436, 37.8075),
         (-122.4335, 37.8065), (-122.4325, 37.8075), (-122.431, 37.8095), (-122.4295, 37.8075), (-122.428, 37.8088),
         (-122.4265, 37.807), (-122.4245, 37.8058), (-122.4215, 37.806), (-122.4205, 37.8078), (-122.4175, 37.8078),
         (-122.414, 37.8085), (-122.4105, 37.8098), (-122.4075, 37.8082), (-122.403, 37.8065), (-122.399, 37.8035),
         (-122.396, 37.8), (-122.393, 37.7955), (-122.389, 37.791), (-122.3875, 37.786), (-122.387, 37.78),
         (-122.385, 37.765)],
        // Marin Headlands and Sausalito
        [(-122.6, 37.83), (-122.54, 37.825), (-122.53, 37.8155), (-122.523, 37.82), (-122.51, 37.8235),
         (-122.497, 37.8265), (-122.4855, 37.826), (-122.4785, 37.8255), (-122.475, 37.8295), (-122.4775, 37.833),
         (-122.4715, 37.8345), (-122.4705, 37.838), (-122.4745, 37.844), (-122.4775, 37.851), (-122.48, 37.857),
         (-122.4855, 37.8635), (-122.4925, 37.869), (-122.497, 37.876), (-122.5, 37.91), (-122.6, 37.91)],
        // Tiburon and Belvedere
        [(-122.49, 37.91), (-122.478, 37.888), (-122.47, 37.879), (-122.4655, 37.871), (-122.4615, 37.8645),
         (-122.457, 37.8645), (-122.4535, 37.8695), (-122.4505, 37.8735), (-122.445, 37.8775), (-122.437, 37.8805),
         (-122.428, 37.887), (-122.418, 37.91)],
        angelIsland,
        // Alcatraz
        [(-122.4262, 37.8262), (-122.4228, 37.8283), (-122.4196, 37.827), (-122.4232, 37.8249)],
        // Treasure Island
        [(-122.3795, 37.8155), (-122.381, 37.8285), (-122.3745, 37.833), (-122.3625, 37.831), (-122.3605, 37.8185),
         (-122.3675, 37.8135)],
        // Yerba Buena Island
        [(-122.3735, 37.8095), (-122.3695, 37.8135), (-122.3625, 37.8125), (-122.3585, 37.8085), (-122.3635, 37.8045),
         (-122.3705, 37.8055)],
        // Oakland and Emeryville
        [(-122.345, 37.76), (-122.342, 37.785), (-122.335, 37.798), (-122.322, 37.812), (-122.31, 37.824),
         (-122.3, 37.845), (-122.298, 37.91), (-122.2, 37.91), (-122.2, 37.76)],
    ]

    /// Named because the temperature key measures off its shore.
    private static let angelIsland = [(-122.4475, 37.8625), (-122.4445, 37.8685), (-122.436, 37.8715), (-122.4255, 37.8695), (-122.4185, 37.8625),
        (-122.4205, 37.854), (-122.4295, 37.8505), (-122.4405, 37.8525)]

    private static let muniPier = [(-122.4245, 37.8062), (-122.4248, 37.8085), (-122.4242, 37.8102),
                                   (-122.4225, 37.8112), (-122.4205, 37.8113)]
    private static let hydeStPier = [(-122.4212, 37.8068), (-122.4214, 37.8098)]
    private static let goldenGate = [(-122.4775, 37.8105), (-122.479, 37.8255)]
    private static let bayBridge = [[(-122.3885, 37.7895), (-122.372, 37.8075)],
                                    [(-122.359, 37.8115), (-122.315, 37.8225)]]
    private static let aquaticPark = (-122.4228, 37.8082)

    private enum Anchor { case leading, centre, trailing }
    private static let labels: [(String, Double, Double, Anchor)] = [
        ("SAUSALITO", -122.4922, 37.8355, .centre), ("TIBURON", -122.462, 37.884, .centre),
        ("MARIN", -122.52, 37.842, .centre), ("ANGEL\nISLAND", -122.4315, 37.8566, .centre),
        ("ALCATRAZ", -122.4185, 37.8266, .leading), ("GOLDEN GATE", -122.489, 37.8183, .centre),
        ("TREASURE\nISLAND", -122.3705, 37.8235, .centre), ("BAY BRIDGE", -122.3800, 37.7965, .leading),
        ("SAN FRANCISCO", -122.447, 37.792, .centre),
    ]

    // MARK: - Land mask

    /// Rasterised once, at roughly 40 m a cell — fine enough to keep the cove open.
    private static let mask = (lon: -122.6, lat: 37.76, cell: 0.0004, columns: 1000, rows: 375)
    private static let water: [UInt8] = {
        var bytes = [UInt8](repeating: 0, count: mask.columns * mask.rows)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: mask.columns, height: mask.rows,
                                          bitsPerComponent: 8, bytesPerRow: mask.columns,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            for shape in land {
                context.addLines(between: shape.map {
                    CGPoint(x: ($0.0 - mask.lon) / mask.cell, y: ($0.1 - mask.lat) / mask.cell)
                })
                context.closePath()
                context.fillPath()
            }
        }
        return bytes
    }()

    static func isLand(_ lon: Double, _ lat: Double) -> Bool {
        let x = (lon - mask.lon) / mask.cell, y = (lat - mask.lat) / mask.cell
        guard x >= 0, y >= 0, x < Double(mask.columns), y < Double(mask.rows) else { return true }
        // Bitmap rows run top-down; the context drew bottom-up.
        return water[(mask.rows - 1 - Int(y)) * mask.columns + Int(x)] > 127
    }

    // MARK: - Flow

    /// The channels the flood follows, each with a strength; ebb is the same field reversed.
    /// ponytail: a sketch of the bay's flow scaled by the one Gate station, not a model.
    /// Swap in NOAA SFBOFS u/v on a grid if the map has to be right street by street.
    private static let channels: [([(Double, Double)], Double)] = [
        ([(-122.6, 37.812), (-122.53, 37.815), (-122.49, 37.818), (-122.465, 37.818), (-122.44, 37.8175),
          (-122.415, 37.8165), (-122.395, 37.811), (-122.38, 37.8), (-122.37, 37.787), (-122.36, 37.77)], 1),
        ([(-122.49, 37.818), (-122.465, 37.828), (-122.452, 37.845), (-122.448, 37.862), (-122.44, 37.876),
          (-122.42, 37.885), (-122.39, 37.892)], 0.65),
        ([(-122.49, 37.818), (-122.455, 37.83), (-122.425, 37.838), (-122.4, 37.84), (-122.375, 37.842),
          (-122.355, 37.85), (-122.33, 37.87)], 0.8),
        ([(-122.47, 37.832), (-122.468, 37.85), (-122.475, 37.865), (-122.488, 37.878)], 0.3),
        ([(-122.475, 37.8125), (-122.45, 37.8105), (-122.43, 37.8115), (-122.41, 37.8125), (-122.4, 37.809)], 0.35),
    ]

    private static let grid = (lon: -122.6, lat: 37.76, cell: 0.001, columns: 400, rows: 150)

    /// Unit flood velocity per cell, x scaled like `kx` so both axes share a length.
    private static let field: (x: [Float], y: [Float]) = {
        let lines = channels.map { line, strength in (line.map { ($0.0 * kx, $0.1) }, strength) }
        let gate = (x: -122.478 * kx, y: 37.818), sigma = 0.0075
        var fx = [Float](repeating: 0, count: grid.columns * grid.rows), fy = fx
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let lon = grid.lon + Double(column) * grid.cell, lat = grid.lat + Double(row) * grid.cell
                let x = lon * kx, y = lat
                // A faint eastward drift, so open water between channels isn't dead.
                var vx = 0.12, vy = 0.0
                for (line, strength) in lines {
                    var best = Double.infinity, tx = 0.0, ty = 0.0
                    for (a, b) in zip(line, line.dropFirst()) {
                        let dx = b.0 - a.0, dy = b.1 - a.1, length = dx * dx + dy * dy
                        let u = min(1, max(0, ((x - a.0) * dx + (y - a.1) * dy) / length))
                        let ex = a.0 + u * dx - x, ey = a.1 + u * dy - y, distance = ex * ex + ey * ey
                        if distance < best { best = distance; tx = dx / length.squareRoot(); ty = dy / length.squareRoot() }
                    }
                    let weight = exp(-best / (sigma * sigma))
                    vx += strength * weight * tx
                    vy += strength * weight * ty
                }
                // Outside the Gate the ocean funnels in from everywhere.
                if lon < -122.49 {
                    let dx = gate.x - x, dy = gate.y - y, distance = hypot(dx, dy) + 1e-6
                    let pull = 0.5 * exp(-distance / 0.04)
                    vx += pull * dx / distance
                    vy += pull * dy / distance
                }
                // The Gate is the narrows; everything runs hardest there.
                let narrows = 1 + 0.9 * exp(-((x - gate.x) * (x - gate.x) + (y - gate.y) * (y - gate.y)) / 0.000144)
                // Muni Pier holds the cove nearly still whatever the bay is doing.
                let cove = lon > -122.4255 && lon < -122.4195 && lat > 37.8055 && lat < 37.8112 ? 0.1 : 1
                fx[row * grid.columns + column] = Float(vx * narrows * cove)
                fy[row * grid.columns + column] = Float(vy * narrows * cove)
            }
        }
        return (fx, fy)
    }()

    /// Flood velocity at a point, (east, north).
    static func flow(_ lon: Double, _ lat: Double) -> (Double, Double) {
        let x = (lon - grid.lon) / grid.cell, y = (lat - grid.lat) / grid.cell
        guard x >= 0, y >= 0, x < Double(grid.columns), y < Double(grid.rows) else { return (0, 0) }
        let index = Int(y) * grid.columns + Int(x)
        return (Double(field.x[index]), Double(field.y[index]))
    }

    /// Which of the five inks: cool at the Gate, warmer east and north.
    /// ponytail: a stylised gradient by position, not measured temperature. One sensor
    /// can't map the bay; SFBOFS carries a temperature grid if this ever has to be real.
    static func hue(_ lon: Double, _ lat: Double) -> Int {
        max(0, min(4, Int(((lon + 122.53) / 0.16 + (lat - 37.8) * 4) * 5)))
    }

    // MARK: - Drawing

    static func drawLand(in context: inout GraphicsContext, frame: Frame,
                         water: (low: Double, high: Double)?) {
        func path(_ points: [(Double, Double)]) -> [CGPoint] { points.map { frame.point($0.0, $0.1) } }

        var shore = Path()
        for shape in land {
            shore.addLines(path(shape))
            shore.closeSubpath()
        }
        // Paper first, so a trail clipping a corner of land never shows through the dots.
        context.fill(shore, with: .color(Theme.paper))

        var dots = Path()
        let pitch: CGFloat = 2.8
        for (row, y) in stride(from: 0, through: frame.size.height, by: pitch * 0.87).enumerated() {
            for x in stride(from: row.isMultiple(of: 2) ? 0 : pitch / 2, through: frame.size.width, by: pitch) {
                let (lon, lat) = frame.coordinate(CGPoint(x: x, y: y))
                if isLand(lon, lat) { dots.addEllipse(in: CGRect(x: x - 0.62, y: y - 0.62, width: 1.24, height: 1.24)) }
            }
        }
        context.fill(dots, with: .color(Theme.ink.opacity(0.55)))
        context.stroke(shore, with: .color(Theme.ink), lineWidth: 0.75)

        for (span, weight) in [(goldenGate, 1.8)] + bayBridge.map({ ($0, 1.2) }) {
            var line = Path()
            line.addLines(path(span))
            context.stroke(line, with: .color(Theme.paper), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.stroke(line, with: .color(Theme.ink), style: StrokeStyle(lineWidth: weight, lineCap: .round))
        }
        for pier in [muniPier, hydeStPier] {
            var line = Path()
            line.addLines(path(pier))
            context.stroke(line, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }

        for (name, lon, lat, anchor) in labels {
            label(name, at: frame.point(lon, lat), anchor: anchor, color: Theme.ink, in: &context)
        }

        let park = frame.point(aquaticPark.0, aquaticPark.1)
        let tag = CGPoint(x: park.x + 10, y: park.y - 14)
        var leader = Path()
        leader.move(to: CGPoint(x: park.x, y: park.y - 3))
        leader.addLine(to: CGPoint(x: tag.x - 2, y: tag.y + 3))
        context.stroke(leader, with: .color(Theme.spot), lineWidth: 0.8)
        let dot = CGRect(x: park.x - 3.2, y: park.y - 3.2, width: 6.4, height: 6.4)
        context.fill(Path(ellipseIn: dot), with: .color(Theme.spot))
        context.stroke(Path(ellipseIn: dot), with: .color(Theme.paper), lineWidth: 1.4)
        label("AQUATIC PARK", at: tag, anchor: .leading, color: Theme.spot, in: &context)

        // The key, in open water between Angel Island and Treasure Island.
        // ponytail: the hues are laid out by position (`hue`), not read off a temperature
        // grid, so the ends are today's real range at the one sensor but the colours between
        // are not placed by it. SFBOFS's temperature grid would make the whole map agree.
        guard let water else { return }
        let low = degrees(water.low), high = degrees(water.high)
        // Each reading centres under its end of the bar. The high one stops at the page
        // margin, level with the masthead's time; the bar then runs west until it is as far
        // from Angel Island's shore as its east end is from the screen's edge.
        let highWidth = context.resolve(Text(high).font(Theme.micro(6.6)).tracking(1.2))
            .measure(in: frame.size).width
        let y = frame.point(0, 37.8509).y
        let right = CGPoint(x: frame.size.width - Theme.margin - highWidth / 2, y: y)
        let angel = angelIsland.map { frame.point($0.0, $0.1) }
        let gap = frame.size.width - right.x
        var left = right
        while left.x > 0, distance(from: CGPoint(x: left.x - 0.5, y: y), to: angel) >= gap {
            left.x -= 0.5
        }
        var bar = Path()
        bar.move(to: left)
        bar.addLine(to: right)
        context.stroke(bar, with: .color(Theme.paper), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        context.stroke(bar, with: .linearGradient(Gradient(colors: hues), startPoint: left, endPoint: right),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        label(low, at: CGPoint(x: left.x, y: y + 9), anchor: .centre, color: Theme.ink, in: &context)
        label(high, at: CGPoint(x: right.x, y: y + 9), anchor: .centre, color: Theme.ink, in: &context)
    }

    /// Nearest approach of a point to a closed outline.
    private static func distance(from point: CGPoint, to outline: [CGPoint]) -> CGFloat {
        zip(outline, outline.dropFirst() + outline.prefix(1)).map { a, b in
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let u = length > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
            return hypot(a.x + u * dx - point.x, a.y + u * dy - point.y)
        }.min() ?? .infinity
    }

    /// One decimal, like the strip's WATER reading: a day's range is often under a degree.
    private static func degrees(_ value: Double) -> String { String(format: "%.1f°F", value) }

    /// Small caps with a paper halo, so a name stays legible over moving water. A `\n`
    /// stacks the name in lines centred on `point`, for an island to hold it inside.
    private static func label(_ name: String, at point: CGPoint, anchor: Anchor, color: Color,
                              in context: inout GraphicsContext) {
        let unit: UnitPoint = switch anchor {
        case .leading: .leading
        case .centre: .center
        case .trailing: .trailing
        }
        let lines = name.split(separator: "\n").map(String.init)
        let leading: CGFloat = 8.5
        for (row, line) in lines.enumerated() {
            let text = Text(line).font(Theme.micro(6.6)).tracking(1.2)
            let at = CGPoint(x: point.x, y: point.y + (CGFloat(row) - CGFloat(lines.count - 1) / 2) * leading)
            let halo = context.resolve(text.foregroundStyle(Theme.paper))
            for (dx, dy) in [(-1.2, 0.0), (1.2, 0), (0, -1.2), (0, 1.2), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
                context.draw(halo, at: CGPoint(x: at.x + dx, y: at.y + dy), anchor: unit)
            }
            context.draw(context.resolve(text.foregroundStyle(color)), at: at, anchor: unit)
        }
    }
}
