import SwiftUI

/// One screenful, and only ever one screenful. There is no scroll view anywhere in the
/// app: everything above the two figures is fixed height, everything below is fixed
/// height, and the figures absorb whatever is left. On a shorter phone they get shorter;
/// nothing ever moves off the bottom edge.
///
/// Reading order is the order a swimmer wants it in — when to go, then today at a glance,
/// then what the water is right now, then the two figures behind the call, then the three
/// routes. The cove is last, not first, because it is never the question.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var curve: [TideSample] = []
    @State private var extremes: [TideExtreme] = []
    @State private var events: [CurrentEvent] = []
    @State private var samples: [CurrentSample] = []
    @State private var forecast: [WeatherHour] = []
    @State private var waterTemp: WaterTempReading?
    @State private var now = Date()
    @State private var banner = Banner.none
    @State private var showingTable = false
    @State private var range = ChartRange.h24
    /// Where the tide figure was last scrubbed to. Nil tracks live `now`.
    @State private var marker: Date?
    /// The grid cell last tapped. Nil means the route rows below are reading live `now`.
    @State private var selectedCell: Date?

    /// Derived on refresh rather than in a computed property: the grid is 120 scans of
    /// the current samples and the body is re-evaluated far more often than the data
    /// changes.
    @State private var west: SwimWindow?
    @State private var east: SwimWindow?
    /// Day offset × hour, each the better of the two exposed routes.
    @State private var grid: [[Double]] = []

    private enum ChartRange { case h24, d4 }

    /// §5.8. A refresh failure the cache can still cover within TTL stays `.none` —
    /// the spec asks for no visible difference there.
    private enum Banner: Equatable {
        case none
        case lastData(Date)
        case noData
    }

    /// The route the headline leads with: whichever window opens first. It is the one
    /// shaded on the tide figure and boxed on the ribbon and the grid.
    private var headline: (window: SwimWindow, label: String)? {
        switch (west, east) {
        case let (west?, east?): west.start <= east.start
            ? (west, "WEST WINDOW") : (east, "EAST WINDOW")
        case let (west?, nil): (west, "WEST WINDOW")
        case let (nil, east?): (east, "EAST WINDOW")
        case (nil, nil): nil
        }
    }

    private var slacks: [SlackWindow] {
        Conditions.slackWindows(events: events, samples: samples)
    }

    private var route: (routes: [RouteVerdict], advisory: String?) {
        Conditions.routeRead(at: now, samples: samples, events: events, forecast: forecast)
    }

    /// What the route rows show: live conditions, unless a grid cell is selected, in
    /// which case it is that hour's conditions instead. The advisory banner above still
    /// reads off live `now` — a hypothetical gale ten hours from now shouldn't interrupt
    /// the sheet today.
    private var displayedRoutes: [RouteVerdict] {
        guard let selectedCell else { return route.routes }
        return Conditions.routeRead(at: selectedCell, samples: samples, events: events,
                                    forecast: forecast).routes
    }

    /// 24H centres the day the swimmer is standing in; 5D is the whole fetched range,
    /// which is what makes the tide figure comparable to the grid under it.
    private var window: (start: Date, end: Date) {
        let full = Conditions.chartWindow(now: now)
        guard range == .h24 else { return full }
        let start = Conditions.calendar.startOfDay(for: now)
        return (start, min(start.addingTimeInterval(24 * 3600), full.end))
    }

    var body: some View {
        VStack(spacing: 0) {
            Masthead(now: now)
            notice
            SwimWindowPair(west: west, east: east)
            DayRibbon(hours: grid.first ?? [], highlight: headline?.window, now: now)
            NowStrip(height: Conditions.height(at: marker ?? now, in: curve),
                     rising: Conditions.isRising(at: marker ?? now, in: curve),
                     water: waterTemp?.temperature,
                     weather: Conditions.weather(at: marker ?? now, in: forecast),
                     label: marker.map { "TIDE AT " + Conditions.handClock($0).uppercased() }
                         ?? "TIDE NOW")
            figures
            selectionNotice
            RouteRows(routes: displayedRoutes)
            footer
        }
        .padding(.top, 8)
        .background(Theme.paper)
        .sheet(isPresented: $showingTable) {
            TideTable(extremes: extremes, slacks: slacks, marker: now) { _ in
                showingTable = false
            }
            .background(Theme.paper)
            .presentationDetents([.height(TideTable.height)])
        }
        .onChange(of: scenePhase) { _, phase in
            // Pull-to-refresh went with the scroll view. Returning to the app is the
            // everyday retry; the notice row is tappable for the rest (§5.8).
            if phase == .active { Task { await refresh() } }
        }
        .task { await refresh() }
    }

    // MARK: - Figures

    /// The only flexible block on the sheet. It is handed the leftover height and splits
    /// it between the two figures in the proportion the mockup used, so a short phone
    /// shrinks both rather than clipping one.
    private var figures: some View {
        GeometryReader { geometry in
            let space = max(geometry.size.height - 2 * FigureCaption.height, 160)
            VStack(spacing: 0) {
                FigureCaption(left: "TIDE CHART", right: range == .h24 ? "24 HR" : "4 DAY")
                TideFigure(curve: curve, samples: samples, window: window,
                           highlight: headline?.window,
                           highlightLabel: headline?.label ?? "", now: marker ?? now,
                           onScrub: { marker = $0 })
                    .frame(height: space * 0.46)
                    .padding(.horizontal, Theme.margin)
                FigureCaption(left: "UPCOMING EAST/WEST WINDOWS",
                              right: "GOOD ■ FAIR ▨ POOR □")
                WindowGrid(days: grid, highlight: headline?.window, now: now,
                           selected: selectedCell, onSelect: { selectedCell = $0 })
                    .frame(height: space * 0.54)
                    .padding(.horizontal, Theme.margin)
            }
        }
    }

    /// Fixed height whether or not a cell is selected, so tapping the grid never
    /// reflows the figures above it.
    @ViewBuilder
    private var selectionNotice: some View {
        if let cell = selectedCell {
            MicroLabel(text: "CONDITIONS FOR " + Self.stamp.string(from: cell)
                .uppercased() + " — TAP TO CLEAR", size: 7.6, tracking: 1.1, color: Theme.spot)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 20)
                .contentShape(Rectangle())
                .onTapGesture { selectedCell = nil }
        } else {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { showingTable = true } label: {
                MicroLabel(text: "TABLE", size: 8.4, tracking: 1.43)
            }
            Spacer()
            HStack(spacing: 6) {
                rangeButton("24H", .h24)
                MicroLabel(text: "·", size: 8.4, color: Theme.hair)
                rangeButton("4D", .d4)
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
        .padding(.top, 14)
    }

    private func rangeButton(_ label: String, _ value: ChartRange) -> some View {
        Button { range = value } label: {
            MicroLabel(text: label, size: 8.4, tracking: 1.43,
                       color: range == value ? Theme.ink : Theme.mute)
        }
    }

    // MARK: - Notice row

    /// One row, under the masthead, for the two things that have to interrupt: a weather
    /// advisory and a dead connection. The advisory wins — a gale outranks stale data.
    @ViewBuilder
    private var notice: some View {
        if let advisory = route.advisory {
            noticeText(advisory.uppercased(), color: Theme.spot)
        } else {
            switch banner {
            case .none:
                EmptyView()
            case .lastData(let stored):
                noticeText("NO CONNECTION / SHOWING LAST DATA "
                           + Self.stamp.string(from: stored).uppercased())
            case .noData:
                noticeText("NO CONNECTION / NO DATA")
            }
        }
    }

    private func noticeText(_ text: String, color: Color = Theme.mute) -> some View {
        MicroLabel(text: text, size: 7.6, tracking: 1.1, color: color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 9)
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

    // MARK: - Loading

    /// Renders from cache first, then refreshes each source independently so one dead
    /// endpoint does not blank the sections the others feed (§5.8).
    private func refresh() async {
        now = Date()

        let cached = await Cache.shared.load()
        if let tides = cached.tides {
            curve = tides.value.curve
            extremes = tides.value.extremes
        }
        if let entry = cached.currents { events = entry.value }
        if let entry = cached.currentsFine { samples = entry.value }
        if let entry = cached.weather { forecast = entry.value }
        if let entry = cached.waterTemp { waterTemp = entry.value }
        derive()

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
        derive()
    }

    /// Everything the sheet shows that costs more than a lookup: the two headline windows
    /// and the five-day grid.
    private func derive() {
        west = Conditions.nextWindow(route: .west, samples: samples, events: events,
                                     forecast: forecast, after: now)
        east = Conditions.nextWindow(route: .east, samples: samples, events: events,
                                     forecast: forecast, after: now)
        guard !samples.isEmpty else {
            grid = []
            return
        }
        let midnight = Conditions.calendar.startOfDay(for: now)
        grid = (0..<4).map { day in
            (0..<24).map { hour in
                let time = midnight.addingTimeInterval(Double(day * 24 + hour) * 3600 + 1800)
                // Zeroed in the dark here rather than in each figure, so the ribbon and
                // the grid cannot disagree about which hours a window can live in.
                guard Conditions.isDaylight(time) else { return 0 }
                return Conditions.bestScore(at: time, samples: samples, forecast: forecast)
            }
        }
    }
}
