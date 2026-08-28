import SwiftUI
import UIKit

struct ContentView: View {
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

    /// One screenful, nothing below the fold. The scroll view survives only because
    /// pull-to-refresh is the sole retry path (§5.8) — `minHeight` makes the content
    /// exactly fill the viewport, so there is no scroll range, just the refresh pull.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    bannerRow
                    chartLabelRow
                    TideChart(curve: curve, slacks: slacks, window: window,
                              showsDayLines: range == .h72, now: now, marker: $marker)
                    Readout(height: Conditions.height(at: marker, in: curve), time: marker,
                            showsNow: marker != nowMark, onNow: { select(time: now) })
                        .animation(.easeOut(duration: 0.18), value: marker)
                    // Pins the content block to the bottom, so a state grows upward
                    // into the gap rather than downward off the screen.
                    Spacer(minLength: 0)
                    contentBlock
                    links
                }
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(Theme.bg)
        .refreshable { await refresh() }
        .onChange(of: marker) { tapIfSlackCrossed() }
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

    // MARK: - Chart label row

    private var chartLabelRow: some View {
        HStack {
            Text(stateWord)
                .tracking(0.9)
                .foregroundStyle(Theme.blue)
            Spacer()
            rangeToggle
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 22)
        .padding(.bottom, 2)
    }

    private var stateWord: String {
        guard let rising = Conditions.isRising(at: marker, in: curve) else { return "—" }
        return rising ? "RISING" : "FALLING"
    }

    /// Plain text, no chrome. Each segment is independently tappable.
    private var rangeToggle: some View {
        HStack(spacing: 0) {
            segment("24H", .h24)
            Text(" / ").foregroundStyle(Theme.pillOff)
            segment("72H", .h72)
        }
        .tracking(0.8)
    }

    private func segment(_ title: String, _ value: ChartRange) -> some View {
        Text(title)
            .foregroundStyle(range == value ? Theme.ink : Theme.inkFaint)
            .contentShape(Rectangle())
            .onTapGesture { select(range: value) }
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
