import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var curve: [TideSample] = []
    @State private var extremes: [TideExtreme] = []
    @State private var events: [CurrentEvent] = []
    @State private var samples: [CurrentSample] = []
    @State private var forecast: [WeatherHour] = []
    @State private var waterTemp: WaterTempReading?
    @State private var marker = Date()
    @State private var now = Date()
    @State private var banner = Banner.none
    @State private var markerInSlack = false
    @State private var mode = Mode.conditions
    @State private var range = ChartRange.h24
    /// Centre of the 24H window. Only moves on an explicit act — switching range or
    /// picking a table row — so dragging the marker never slides the window.
    @State private var anchor = Date()

    /// The block between the readout and the bottom links. Everything above it is
    /// identical and stationary in all three.
    private enum Mode { case conditions, table, route }

    private enum ChartRange { case h24, h72 }

    /// §5.8. A refresh failure the cache can still cover within TTL stays `.none` —
    /// the spec asks for no visible difference there.
    private enum Banner: Equatable {
        case none
        case lastData(Date)
        case noData
    }

    private var fullWindow: (start: Date, end: Date) { Conditions.chartWindow(now: now) }

    private var window: (start: Date, end: Date) {
        range == .h24 ? window24(around: anchor) : fullWindow
    }

    /// Centred on `centre`, then slid back inside the data window at either end.
    /// Snapped to the full window's 6-minute grid so the marker keeps landing on
    /// real clock samples rather than on offsets from an arbitrary window start.
    private func window24(around centre: Date) -> (start: Date, end: Date) {
        let span: TimeInterval = 24 * 3600
        let full = fullWindow
        let start = Conditions.snap(
            min(max(centre.addingTimeInterval(-span / 2), full.start),
                full.end.addingTimeInterval(-span)), to: full)
        return (start, start.addingTimeInterval(span))
    }

    private var slacks: [SlackWindow] {
        Conditions.slackWindows(events: events, samples: samples)
    }

    private var velocity: Double? { Conditions.velocity(at: marker, in: samples) }

    private var weather: WeatherHour? { Conditions.weather(at: marker, in: forecast) }

    /// Real now, snapped into the window. The marker sitting anywhere else is what
    /// puts the `NOW` affordance on the readout.
    private var nowMark: Date { Conditions.snap(now, to: window) }

    /// One screenful, and only ever one screenful. No scroll view at all: the chart
    /// absorbs whatever height the header, conditions and links leave it, so the
    /// layout fits every device exactly and nothing can be dragged off either edge.
    var body: some View {
        VStack(spacing: 0) {
            header
            bannerRow
            chart
            contentBlock
            links
        }
        .background(Theme.bg)
        .onChange(of: marker) { tapIfSlackCrossed() }
        .onChange(of: scenePhase) { _, phase in
            // Pull-to-refresh went with the scroll view. Returning to the app is the
            // everyday retry; the banner is tappable for the rest (§5.8).
            if phase == .active { Task { await refresh() } }
        }
        .task {
            now = Date()
            anchor = now
            marker = Conditions.snap(now, to: window)
            await refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 7) {
            Text("Aquatic Park")
                .font(.system(size: 22, weight: .medium))
                .tracking(-0.22)
                .foregroundStyle(Theme.ink)
            Text("NOAA \(API.tideStation) / GOLDEN GATE")
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(Theme.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
    }

    // MARK: - Chart

    /// Three corners of the plot carry what used to sit in the label row above it
    /// and the readout below it: range, height, and the state word. The floor keeps
    /// the plot legible when the tide table is open under it.
    private var chart: some View {
        TideChart(curve: curve, window: window, showsDayLines: range == .h72,
                  now: now, marker: $marker)
            .frame(minHeight: 180, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                rangeToggle
                    .padding(.leading, 12)
                    .padding(.top, 2)
            }
            .overlay(alignment: .topTrailing) {
                heightReadout
                    .padding(.trailing, 22)
                    .padding(.top, 14)
            }
            .overlay(alignment: .bottomLeading) {
                stateWord
                    .padding(.leading, 36)
                    .padding(.bottom, TideChart.axisHeight + 8)
            }
    }

    private var heightReadout: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("HEIGHT")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.inkMuted)
            Text(Conditions.height(at: marker, in: curve)
                    .map { String(format: "%+.2f FT", $0) } ?? "—")
                .font(.system(size: 27, weight: .semibold, design: .monospaced))
                .tracking(-0.6)
                .monospacedDigit()
                .contentTransition(.opacity)
                .foregroundStyle(Theme.ink)
            if marker != nowMark {
                Button { select(time: now) } label: {
                    Text("NOW")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.81)
                        .foregroundStyle(Theme.blue)
                        // Widens the hit area without moving the glyphs.
                        .padding(.leading, 28)
                        .padding(.trailing, 4)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: marker)
    }

    /// Slack is not drawn on the plot any more, so this word is the only place it
    /// shows: scrubbing the marker into a slack window is what reveals it.
    @ViewBuilder
    private var stateWord: some View {
        if let stateText {
            HandwritingText(text: stateText, size: 25)
                .foregroundStyle(Theme.blue)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.18), value: stateText)
                .allowsHitTesting(false)
        }
    }

    private var stateText: String? {
        if isMarkerInSlack { return "Slack tide" }
        guard let rising = Conditions.isRising(at: marker, in: curve) else { return nil }
        return rising ? "Rising tide" : "Falling tide"
    }

    /// Plain text, no chrome. Each segment is independently tappable.
    private var rangeToggle: some View {
        HStack(spacing: 0) {
            segment("24H", .h24)
            segment("72H", .h72)
        }
        .font(.system(size: 10, design: .monospaced))
        .tracking(0.8)
    }

    /// A `Button` rather than a tap gesture, and padded out to a finger: the plot
    /// underneath scrubs on contact, so anything that misses these bounds moves the
    /// marker instead of switching range.
    private func segment(_ title: String, _ value: ChartRange) -> some View {
        Button {
            select(range: value)
        } label: {
            Text(title)
                .foregroundStyle(range == value ? Theme.ink : Theme.inkFaint)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(range == value ? Theme.blue : .clear)
                        .frame(height: 1.5)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The marker keeps its timestamp; only the window around it changes.
    private func select(range value: ChartRange) {
        guard range != value else { return }
        anchor = marker
        range = value
    }

    // MARK: - Content block

    @ViewBuilder
    private var contentBlock: some View {
        Group {
            switch mode {
            case .conditions:
                ConditionsStrip(water: waterTemp?.temperature,
                                waterEstimated: marker.timeIntervalSince(now) > 3600,
                                weather: weather)
            case .table:
                TideTable(extremes: extremes, slacks: slacks, marker: marker,
                          onSelect: select(time:))
            case .route:
                RouteRead(routes: Conditions.routeRead(
                              velocity: velocity,
                              nextSlack: Conditions.nextSlack(after: marker, in: events)?.time,
                              from: marker,
                              wind: weather?.windSpeed),
                          gate: Conditions.gateSummary(velocity: velocity))
            }
        }
        .id(mode)
        .transition(.opacity)
        .simultaneousGesture(swipeDown)
    }

    /// Swiping down anywhere on the content block returns to State A. Simultaneous
    /// so it does not steal the scroll or pull-to-refresh.
    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { drag in
            guard mode != .conditions,
                  drag.translation.height > 40,
                  drag.translation.height > abs(drag.translation.width) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { mode = .conditions }
        }
    }

    /// A table row moves the marker, re-centring the 24H window only if the event
    /// falls outside it.
    private func select(time: Date) {
        var target = window
        if range == .h24, time < target.start || time > target.end {
            anchor = time
            target = window24(around: time)
        }
        withAnimation(.easeOut(duration: 0.25)) {
            marker = Conditions.snap(time, to: target)
        }
    }

    // MARK: - Bottom links

    private var links: some View {
        HStack {
            link("TIDE TABLE", .table)
            Spacer()
            link("ROUTE READ", .route)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
    }

    private func link(_ title: String, _ target: Mode) -> some View {
        Text(title)
            .tracking(0.945)
            .foregroundStyle(mode == target ? Theme.blue
                             : mode == .conditions ? Theme.ink : Theme.inkFaint)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = mode == target ? .conditions : target
                }
            }
    }

    // MARK: - Connection banner (§5.8)

    /// One row below the header. No alert, no modal, no retry button —
    /// pull-to-refresh handles retry.
    @ViewBuilder
    private var bannerRow: some View {
        switch banner {
        case .none:
            EmptyView()
        case .lastData(let stored):
            bannerText("NO CONNECTION / SHOWING LAST DATA "
                       + Self.stamp.string(from: stored).uppercased())
        case .noData:
            bannerText("NO CONNECTION / NO DATA")
        }
    }

    private func bannerText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Theme.inkMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            .contentShape(Rectangle())
            .onTapGesture { Task { await refresh() } }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    // MARK: - Haptics (§5.3)

    private var isMarkerInSlack: Bool {
        slacks.contains { marker >= $0.start && marker <= $0.end }
    }

    /// A light tap on crossing into or out of a slack window, and nowhere else.
    /// Membership is only re-read when the marker moves, so data arriving under a
    /// stationary marker cannot fire it.
    private func tapIfSlackCrossed() {
        let inside = isMarkerInSlack
        guard inside != markerInSlack else { return }
        markerInSlack = inside
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Loading

    /// Renders from cache first, then refreshes each source independently so one
    /// dead endpoint does not blank the sections the others feed (§5.8). Leaves the
    /// marker where the swimmer put it — only the window is re-clamped, in case a
    /// refresh crosses local midnight and shifts it.
    private func refresh() async {
        now = Date()
        marker = Conditions.snap(marker, to: window)

        let cached = await Cache.shared.load()
        if let tides = cached.tides {
            curve = tides.value.curve
            extremes = tides.value.extremes
        }
        if let entry = cached.currents { events = entry.value }
        if let entry = cached.currentsFine { samples = entry.value }
        if let entry = cached.weather { forecast = entry.value }
        if let entry = cached.waterTemp { waterTemp = entry.value }

        async let curveTask = API.tideCurve()
        async let extremesTask = API.tideExtremes()
        async let eventsTask = API.currents()
        async let samplesTask = API.currentsFine()
        async let weatherTask = API.weather()
        async let waterTask = API.waterTemperature()

        var failed = false

        if let fresh = try? await curveTask, let freshExtremes = try? await extremesTask {
            curve = fresh
            extremes = freshExtremes
            await Cache.shared.update {
                $0.tides = Entry(TidePayload(curve: fresh, extremes: freshExtremes))
            }
        } else {
            failed = true
        }
        if let fresh = try? await eventsTask {
            events = fresh
            await Cache.shared.update { $0.currents = Entry(fresh) }
        } else {
            failed = true
        }
        if let fresh = try? await samplesTask {
            samples = fresh
            await Cache.shared.update { $0.currentsFine = Entry(fresh) }
        } else {
            failed = true
        }
        if let fresh = try? await weatherTask {
            forecast = fresh
            await Cache.shared.update { $0.weather = Entry(fresh) }
        } else {
            failed = true
        }
        if let fresh = try? await waterTask {
            waterTemp = fresh
            await Cache.shared.update { $0.waterTemp = Entry(fresh) }
        } else {
            failed = true
        }

        let freshness = await Cache.shared.load().freshness
        banner = !failed || !freshness.stale ? .none
            : freshness.oldest.map(Banner.lastData) ?? .noData
        markerInSlack = isMarkerInSlack
    }
}
