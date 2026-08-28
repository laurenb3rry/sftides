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

    /// §5.8. A refresh failure the cache can still cover within TTL stays `.none` —
    /// the spec asks for no visible difference there.
    private enum Banner: Equatable {
        case none
        case lastData(Date)
        case noData
    }

    private var window: (start: Date, end: Date) { Conditions.chartWindow(now: now) }

    private var slacks: [SlackWindow] {
        Conditions.slackWindows(events: events, samples: samples)
    }

    private var velocity: Double? { Conditions.velocity(at: marker, in: samples) }

    private var weather: WeatherHour? { Conditions.weather(at: marker, in: forecast) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                bannerRow
                blueRule
                TideChart(curve: curve, window: window, now: now, marker: $marker)
                Readout(height: Conditions.height(at: marker, in: curve), time: marker)
                    .animation(.easeOut(duration: 0.18), value: marker)
                blueRule
                ConditionsStrip(water: waterTemp?.temperature,
                                waterEstimated: marker.timeIntervalSince(now) > 3600,
                                weather: weather)
                blueRule
                TideTable(extremes: extremes, slacks: slacks, marker: marker)
                blueRule
                RouteRead(routes: Conditions.routeRead(
                              velocity: velocity,
                              nextSlack: Conditions.nextSlack(after: marker, in: events)?.time,
                              from: marker,
                              wind: weather?.windSpeed),
                          gate: Conditions.gateSummary(velocity: velocity))
            }
        }
        .background(Theme.bg)
        .refreshable { await refresh() }
        .onChange(of: marker) { tapIfSlackCrossed() }
        .task {
            now = Date()
            marker = Conditions.snap(now, to: window)
            await refresh()
        }
    }

    // MARK: - Header (§5.2)

    private var header: some View {
        VStack(spacing: 6) {
            Text("Aquatic Park")
                .font(.system(size: 23, weight: .medium))
                .tracking(-0.23)
                .foregroundStyle(Theme.ink)
            Text("NOAA \(API.tideStation) / GOLDEN GATE")
                .font(.system(size: 10.5, design: .monospaced))
                .tracking(0.945)
                .foregroundStyle(Theme.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    /// The structural device of the whole screen — every major section is bounded by one.
    private var blueRule: some View {
        Rectangle().fill(Theme.blue).frame(height: 2)
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
        formatter.dateFormat = "EEE HH:mm"
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
