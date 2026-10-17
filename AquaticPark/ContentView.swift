import SwiftUI

/// One screenful, and only ever one screenful. There is no scroll view anywhere in the
/// app: everything above the two figures is fixed height, everything below is fixed
/// height, and the figures absorb whatever is left. On a shorter phone they get shorter;
/// nothing ever moves off the bottom edge.
///
/// Reading order is the order a swimmer wants it in — the bay moving, then when to go,
/// then the tide figure behind the call, then what the water is at the time it's reading,
/// then the three routes. The cove is last, not first, because it is never the question.
/// The figure's caption flips everything from the graph down to the tide table and back.
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
    /// The figure block shows the tide table instead of the graph, strip and routes.
    @State private var showingTable = false
    /// Which of the fetched days the tide figure is on, as an offset from today.
    @State private var day = 0
    /// Where the tide figure was last scrubbed to. Nil tracks live `now`.
    @State private var marker: Date?
    /// The grid cell last tapped. Nil means the route rows below are reading live `now`.
    @State private var selectedCell: Date?

    /// Derived on refresh rather than in a computed property: it is 96 scans of the
    /// current samples and the body is re-evaluated far more often than the data changes.
    /// Day offset × hour, each the better of the two exposed routes.
    @State private var grid: [[Double]] = []

    /// Every west or east swim window in the fetched range, for the tide figure's dots.
    /// Derived alongside `grid` for the same reason: each is a scan of the current samples.
    @State private var swims: [(range: ClosedRange<Date>, east: Bool)] = []

    /// Breathing room between sections that would otherwise abut. Subtracted out of
    /// `figures`' flexible space wherever it falls inside the GeometryReader, so adding
    /// air between elements never grows the chart or the grid.
    private let sectionGap: CGFloat = 10
    /// Between the strip and the route rows: the readings overhang the strip by 2pt, so
    /// this leaves `ruleGap` between them and the routes' rule.
    private let routeGap: CGFloat = Theme.ruleGap + 2
    /// What the graph's toggle row (22pt), the old footer (32pt) and the wider gaps used to
    /// take, less what the even rule gaps took back (against a 31pt caption, a 38pt strip,
    /// an 8pt route gap and 72pt of routes). Held back so the figure keeps the height it
    /// had; the paper gathers at the foot.
    private var freedHeight: CGFloat {
        64 - (FigureCaption.height - 31) - (NowStrip.viewHeight - 38) - (routeGap - 8)
            - (RouteRows.height - 72)
    }

    /// §5.8. A refresh failure the cache can still cover within TTL stays `.none` —
    /// the spec asks for no visible difference there.
    private enum Banner: Equatable {
        case none
        case lastData(Date)
        case noData
    }

    /// Reads off the scrub marker rather than live `now`, so dragging the tide figure
    /// walks the headline through the window it's pointing at instead of leaving it
    /// pinned to the moment the data last refreshed.
    private var west: SwimWindow? {
        Conditions.nextWindow(route: .west, samples: samples, events: events,
                              forecast: forecast, after: marker ?? now)
    }
    private var east: SwimWindow? {
        Conditions.nextWindow(route: .east, samples: samples, events: events,
                              forecast: forecast, after: marker ?? now)
    }

    private var slacks: [SlackWindow] {
        Conditions.slackWindows(events: events, samples: samples)
    }

    private var route: (routes: [RouteVerdict], advisory: String?) {
        Conditions.routeRead(at: now, samples: samples, events: events, forecast: forecast)
    }

    /// What the route rows show: the conditions at whatever time the sheet is reading —
    /// a selected grid cell, else the scrub marker, else live `now` — so dragging the tide
    /// figure walks the GO along with the map and the strip. The advisory banner above
    /// still reads off live `now`: a hypothetical gale ten hours from now shouldn't
    /// interrupt the sheet today.
    private var displayedRoutes: [RouteVerdict] {
        guard let time = selectedCell ?? marker else { return route.routes }
        return Conditions.routeRead(at: time, samples: samples, events: events,
                                    forecast: forecast).routes
    }

    var body: some View {
        VStack(spacing: 0) {
            Masthead(now: now)
            notice
            // Reads the same time as the strip, so scrubbing the figure runs the bay too.
            CurrentsMap(knots: Conditions.velocity(at: marker ?? now, in: samples),
                        water: waterTemp?.range)
                .containerRelativeFrame(.vertical) { length, _ in length * 0.26 }
            SwimWindowPair(west: west, east: east)
            figures
        }
        .padding(.top, 8)
        .background(Theme.paper)
        .onChange(of: scenePhase) { _, phase in
            // Pull-to-refresh went with the scroll view. Returning to the app is the
            // everyday retry; the notice row is tappable for the rest (§5.8).
            if phase == .active { Task { await refresh() } }
        }
        .task { await refresh() }
    }

    // MARK: - Figures

    /// The only flexible block on the sheet: the tide figure takes whatever height is
    /// left once the strip and routes have theirs, so a short phone shrinks it rather
    /// than clipping anything. With TABLE picked, the table drops down over all of it.
    ///
    /// The window grid is off the sheet for now. Its data (`grid`, `selectedCell`) is
    /// still derived — the day stepper reads `grid` — and `windowGrid` is kept whole
    /// for putting back.
    private var figures: some View {
        GeometryReader { geometry in
            let space = max(geometry.size.height - FigureCaption.height - NowStrip.viewHeight
                             - sectionGap - RouteRows.height - routeGap - freedHeight, 120)
            VStack(spacing: 0) {
                FigureCaption(left: "", right: "", leading: AnyView(figureTabs),
                              // Hidden rather than removed, so the caption keeps its height.
                              trailing: AnyView(dayStepper.opacity(showingTable ? 0 : 1)
                                  .disabled(showingTable)))
                ZStack(alignment: .top) {
                    if showingTable {
                        TideTable(extremes: extremes, slacks: slacks, marker: now) { time in
                            marker = time
                            day = dayOffset(of: time)
                            show(table: false)
                        }
                        .padding(.top, 18)
                        .transition(.move(edge: .top))
                    } else {
                        graph(space: space)
                            .transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
            }
        }
    }

    /// Graph, the readings at the marker, and the three routes — East to the Wharf is
    /// the last line on the sheet.
    private func graph(space: CGFloat) -> some View {
        VStack(spacing: 0) {
            TideFigure(curve: curve, samples: samples, slacks: slacks, swims: swims,
                       fullWindow: Conditions.chartWindow(now: now), day: $day, now: marker ?? now, onScrub: { marker = $0 })
                .frame(height: space)
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, sectionGap)
            NowStrip(height: Conditions.height(at: marker ?? now, in: curve),
                     rising: Conditions.isRising(at: marker ?? now, in: curve),
                     water: waterTemp?.temperature,
                     weather: Conditions.weather(at: marker ?? now, in: forecast),
                     knots: Conditions.velocity(at: marker ?? now, in: samples),
                     label: marker.map { "TIDE AT " + Conditions.handClock($0).uppercased() }
                         ?? "TIDE NOW")
            RouteRows(routes: displayedRoutes)
                .padding(.top, routeGap)
        }
    }

    /// `TIDE GRAPH  TABLE` in the figure's caption: the one picked is in ink.
    private var figureTabs: some View {
        HStack(spacing: 16) {
            tab("TIDE GRAPH", table: false)
            tab("TABLE", table: true)
        }
    }

    private func tab(_ title: String, table: Bool) -> some View {
        Button { show(table: table) } label: {
            MicroLabel(text: title, tracking: 1.29,
                       color: showingTable == table ? Theme.ink : Theme.mute)
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
    }

    private func show(table: Bool) {
        withAnimation(.easeInOut(duration: 0.28)) { showingTable = table }
    }

    /// Not on the sheet for now; see `figures`. Goes back under the strip with
    /// `selectionNotice` below it.
    private func windowGrid(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            FigureCaption(left: "UPCOMING EAST/WEST WINDOWS",
                          right: "GOOD ■ FAIR ▨ POOR □")
            WindowGrid(days: grid, now: now,
                       selected: selectedCell,
                       onSelect: { selectedCell = $0; marker = $0; day = dayOffset(of: $0) },
                       onSelectDay: { select(day: $0) })
                .frame(height: height)
                .padding(.horizontal, Theme.margin)
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
                .onTapGesture {
                    selectedCell = nil
                    marker = nil
                }
        } else {
            Color.clear.frame(height: 20)
        }
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// `< FRI >` in the tide chart's caption. The label has a fixed width so the arrows
    /// stay put whatever the day is called; an arrow greys out at either end of the range.
    private var dayStepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", to: day - 1)
            MicroLabel(text: day == 0 ? "TODAY" : Self.weekday.string(from: date(offset: day)).uppercased(),
                       tracking: 1.29, color: Theme.ink)
                .frame(width: 44)
            stepButton("chevron.right", to: day + 1)
        }
    }

    private func stepButton(_ symbol: String, to target: Int) -> some View {
        let enabled = grid.indices.contains(target)
        return Button { select(day: target) } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.hair)
                // Grows the hit area without growing the caption.
                .frame(width: 18)
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Moves the figure to a day and drops any grid selection, which belongs to the day
    /// it was made on.
    private func select(day target: Int) {
        day = target
        selectedCell = nil
        marker = nil
    }

    private func date(offset: Int) -> Date {
        Conditions.calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }

    private func dayOffset(of time: Date) -> Int {
        Conditions.calendar.dateComponents(
            [.day], from: Conditions.calendar.startOfDay(for: now),
            to: Conditions.calendar.startOfDay(for: time)).day ?? 0
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

    /// The one thing left that costs more than a lookup: the five-day grid.
    private func derive() {
        guard !samples.isEmpty else {
            grid = []
            swims = []
            return
        }
        let chart = Conditions.chartWindow(now: now)
        swims = [Conditions.SwimRoute.west, .east].flatMap { route in
            Conditions.swimWindows(route: route, samples: samples, events: events,
                                   forecast: forecast, from: chart.start, through: chart.end)
                .map { ($0.start...$0.end, route == .east) }
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
