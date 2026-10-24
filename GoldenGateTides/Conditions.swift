import Foundation

enum Conditions {

    // TUNABLE — calibrate against real swims over a season. The wind numbers are set
    // off a year of hourly Open-Meteo at the cove: median 7, p90 13, p99 19 mph.
    // The current numbers are North Point knots (SFB1205 bin 15 runs to about +2.9 flood,
    // -3.3 ebb), which read higher than the water actually moving inside the cove.
    static let slackThreshold: Double = 0.5      // knots
    static let approachWindow: Double = 60       // minutes; "wait" advice appears within this
    static let calmWind: Double = 12             // mph; above this the cove stops reading CALM
    static let chopWind: Double = 18             // mph; too rough to be outside the cove
    static let northChop: Double = 12            // mph from the north — the opening faces that way
    static let opposedWindPenalty: Double = 4    // mph off chopWind when wind fights the current
    static let galeWind: Double = 25             // mph; nobody should be getting in
    static let outLeg: Double = 25               // minutes swum into slack water
    static let ridingSpeed: Double = 0.1      // knots; the home leg must run faster than this the right way
    static let rainLookback: Double = 24         // hours back to look for a discharge-triggering rain
    /// Share of the buoy-vs-Richmond blend that moves with the current at the opening, per
    /// knot: a flood pulls the water temperature toward the ocean, an ebb toward the bay.
    /// ponytail: a prior, not a fit — there are no swim readings to calibrate it against.
    static let tidalWeightShift: Double = 0.05

    // MARK: - Chart window (§5.3)

    /// Local midnight today to local midnight +3 days. Now is not centred — it sits
    /// wherever it falls in today.
    static func chartWindow(now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = API.zone
        let start = calendar.startOfDay(for: now)
        return (start, calendar.date(byAdding: .day, value: 4, to: start)!)
    }

    /// Nearest 6-minute sample, clamped to the window.
    static func snap(_ time: Date, to window: (start: Date, end: Date)) -> Date {
        let span = window.end.timeIntervalSince(window.start)
        let elapsed = (time.timeIntervalSince(window.start) / 360).rounded() * 360
        return window.start.addingTimeInterval(min(max(elapsed, 0), span))
    }

    // MARK: - Tide height (§4.1)

    /// Linear interpolation between the 6-minute samples. Dense enough that this
    /// is correct to well under 0.01 ft — no spline, no re-derived harmonics.
    static func height(at time: Date, in curve: [TideSample]) -> Double? {
        guard let (a, b, fraction) = bracket(curve, time, \.time) else { return nil }
        return a.height + (b.height - a.height) * fraction
    }

    /// Rising when the height exceeds the value 6 minutes prior. At the very start
    /// of the window there is no prior sample, so compare forward instead.
    static func isRising(at time: Date, in curve: [TideSample]) -> Bool? {
        guard let current = height(at: time, in: curve) else { return nil }
        if let previous = height(at: time.addingTimeInterval(-360), in: curve) {
            return current > previous
        }
        guard let next = height(at: time.addingTimeInterval(360), in: curve) else { return nil }
        return next > current
    }

    // MARK: - Current

    /// Interpolated between the 6-minute samples, the same way tide height is.
    static func velocity(at time: Date, in samples: [CurrentSample]) -> Double? {
        guard let (a, b, fraction) = bracket(samples, time, \.time) else { return nil }
        return a.velocity + (b.velocity - a.velocity) * fraction
    }

    // MARK: - Water temperature

    /// The buoy/Richmond blend at the time it was observed, moved by how much the current
    /// at the opening has changed since: a flood leans the blend toward the ocean buoy
    /// (colder), an ebb toward Richmond (warmer). At the observation time this is exactly
    /// the observed blend. Beyond it, the two sensors are held at their last readings,
    /// since NOAA forecasts neither. A reading cached before the sensors were stored
    /// separately comes back unchanged.
    static func waterTemperature(at time: Date, reading: WaterTempReading?,
                                 samples: [CurrentSample]) -> Double? {
        guard let reading else { return nil }
        guard let richmond = reading.richmond,
              let then = velocity(at: reading.time, in: samples),
              let now = velocity(at: time, in: samples) else { return reading.temperature }
        let weight = min(max(API.buoyWeight + tidalWeightShift * (now - then), 0.5), 1)
        if let buoy = reading.buoy { return weight * buoy + (1 - weight) * richmond }
        // Richmond alone: the same weight, applied to the buoy-below-Richmond gap that the
        // fallback offset implies (which is exactly the offset at the reference weight).
        return richmond + weight * API.richmondOffset / API.buoyWeight
    }

    // MARK: - Weather

    /// Nearest hourly forecast. Open-Meteo publishes on the hour and every cell in
    /// §5.5 renders to integer or one-decimal precision, so interpolating between
    /// hours would not change a single digit on screen.
    static func weather(at time: Date, in hours: [WeatherHour]) -> WeatherHour? {
        hours.min {
            abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time))
        }
    }

    // MARK: - Slack windows (§4.2)

    /// The span around each slack event where |velocity| stays under `slackThreshold`.
    ///
    /// DEVIATION FROM §4.2, which infers the crossings by interpolating between the
    /// MAX_SLACK extrema. Those extrema are too sparse to place the crossing: a
    /// straight line from the peak overstated the window by 47–100% and opened it
    /// 20–27 minutes early, reading "SLACK NOW" while the Gate still ran over 1 kn.
    /// The crossings are measured off the 6-minute product instead, so the only
    /// remaining error is the half-sample edge refined away below.
    ///
    /// `events` still supplies the labelled slack times. A slack at either end of
    /// the response has no neighbour to prove its samples are complete, and a slack
    /// whose samples are missing is skipped rather than guessed.
    static func slackWindows(events: [CurrentEvent], samples: [CurrentSample]) -> [SlackWindow] {
        events.indices.compactMap { i -> SlackWindow? in
            guard events[i].type == .slack, i > 0, i + 1 < events.count else { return nil }
            let slack = events[i]

            // Nearest sample to the labelled slack, which should sit inside the window.
            guard let centre = samples.indices.min(by: {
                abs(samples[$0].time.timeIntervalSince(slack.time))
                    < abs(samples[$1].time.timeIntervalSince(slack.time))
            }), abs(samples[centre].velocity) < slackThreshold else { return nil }

            var low = centre
            while low > 0, abs(samples[low - 1].velocity) < slackThreshold { low -= 1 }
            var high = centre
            while high < samples.count - 1,
                  abs(samples[high + 1].velocity) < slackThreshold { high += 1 }

            return SlackWindow(
                time: slack.time,
                start: edge(outside: low > 0 ? samples[low - 1] : nil, inside: samples[low]),
                end: edge(outside: high < samples.count - 1 ? samples[high + 1] : nil,
                          inside: samples[high])
            )
        }
    }

    /// Refines a window edge to sub-sample precision by interpolating between the
    /// last sample outside the threshold and the first one inside it.
    private static func edge(outside: CurrentSample?, inside: CurrentSample) -> Date {
        guard let outside else { return inside.time }
        let (high, low) = (abs(outside.velocity), abs(inside.velocity))
        guard high > low else { return inside.time }
        let fraction = (high - slackThreshold) / (high - low)
        let span = inside.time.timeIntervalSince(outside.time)
        return outside.time.addingTimeInterval(span * fraction)
    }

    // MARK: - Route read (§4.3)

    private enum Route { case cove, west, east }

    private static let coveName = "Cove"
    private static let westName = "West to Fort Mason"
    private static let eastName = "East to the wharf"

    /// The three routes in fixed order — Cove, West to Fort Mason, East to the wharf —
    /// with exactly one favourable, plus the rare line that says stay out altogether.
    ///
    /// An ebb runs west past the opening and keeps building all the way to the Gate; a
    /// flood runs east toward the wharf. The pick is whichever route has a window open
    /// right now (see `windowOpen`): one leg in slack water, the other in whatever is
    /// running either side of it.
    ///
    /// When neither is open the cove is the answer, and it nearly always is one:
    /// Municipal Pier keeps the current out of it, so only wind reaches in there.
    static func routeRead(at time: Date, samples: [CurrentSample], events: [CurrentEvent],
                          forecast: [WeatherHour]) -> (routes: [RouteVerdict], advisory: String?) {
        let now = velocity(at: time, in: samples)
        let hour = weather(at: time, in: forecast)
        let note = advisory(at: time, in: forecast)

        // No forecast is no wind objection, the same as for the windows.
        let rough = hour.map { roughOutside($0, current: now) } ?? false
        func open(_ route: SwimRoute) -> Bool {
            inWindow(at: time, route: route, samples: samples, forecast: forecast)
        }
        // The cove is the answer whenever neither exposed window is open.
        let pick: Route? = note != nil ? nil
            : rough ? .cove
            : open(.west) ? .west
            : open(.east) ? .east
            : .cove

        /// West and east differ only in their copy; everything deciding them is shared.
        func exposed(_ name: String, _ route: SwimRoute, _ picked: Bool, ride: String,
                     wrongWay: String, withCurrent: String) -> RouteVerdict {
            guard let now else { return unavailable(name) }
            if picked {
                let slackNow = isSlack(now)
                let slackOut = windowOpen(at: time, route: route, slackLeg: .out,
                                          samples: samples, forecast: forecast)
                return RouteVerdict(title: name,
                                    sublabel: slackNow ? "SLACK NOW"
                                        : slackOut ? ride : "SLACK ON THE WAY BACK",
                                    verdict: "GO",
                                    condition: slackNow ? "slack now"
                                        : slackOut ? withCurrent : "slack back",
                                    isFavorable: true)
            }
            if rough, let hour {
                return RouteVerdict(title: name, sublabel: "WIND \(Int(hour.windSpeed)) MPH",
                                    verdict: "CHOP", condition: "chop", isFavorable: false)
            }
            if let wait = minutesUntilOpen(route, after: time, samples: samples,
                                           forecast: forecast) {
                let opens = clock.string(from: time.addingTimeInterval(Double(wait) * 60))
                return RouteVerdict(title: name, sublabel: "OPENS AT \(opens)",
                                    verdict: "WAIT \(wait)M",
                                    condition: "wait \(wait) min", isFavorable: false)
            }
            return RouteVerdict(title: name, sublabel: wrongWay,
                                verdict: "NOT NOW", condition: "wrong way", isFavorable: false)
        }

        return ([
            cove(hour, picked: pick == .cove),
            exposed(westName, .west, pick == .west,
                    ride: "FLOOD CARRIES YOU IN", wrongWay: "EBB RUNS TO THE GATE",
                    withCurrent: "with flood"),
            exposed(eastName, .east, pick == .east,
                    ride: "EBB CARRIES YOU IN", wrongWay: "FLOOD PUSHES EAST",
                    withCurrent: "with ebb"),
        ], note)
    }

    /// Whole minutes until `route`'s window next opens, if that is within
    /// `approachWindow`.
    private static func minutesUntilOpen(_ route: SwimRoute, after time: Date,
                                         samples: [CurrentSample],
                                         forecast: [WeatherHour]) -> Int? {
        stride(from: 5.0, through: approachWindow, by: 5).first {
            inWindow(at: time.addingTimeInterval($0 * 60), route: route,
                     samples: samples, forecast: forecast)
        }.map(Int.init)
    }

    /// Sheltered from the current behind Municipal Pier, so wind-driven only — and
    /// sheltered whether or not the forecast came back, which is what makes it the
    /// failsafe.
    private static func cove(_ hour: WeatherHour?, picked: Bool) -> RouteVerdict {
        guard let hour else {
            return RouteVerdict(title: coveName, sublabel: "SHELTERED ALL DAY",
                                verdict: picked ? "GO" : "—", condition: "sheltered",
                                isFavorable: picked)
        }
        let calm = hour.windSpeed < calmWind
        return RouteVerdict(
            title: coveName,
            sublabel: calm ? "SHELTERED ALL DAY" : "WIND \(Int(hour.windSpeed)) MPH",
            verdict: picked ? "GO" : (calm ? "CALM" : hour.windSpeed < chopWind ? "CHOP" : "WINDY"),
            condition: calm ? "sheltered" : "wind \(Int(hour.windSpeed)) mph",
            isFavorable: picked
        )
    }

    /// The cove opening faces north, so a northerly pushes chop straight through it even
    /// when it is light. Otherwise it takes a real blow — unless the wind is running
    /// against the current, which stands the surface up: the prevailing westerly smooths
    /// a flood and steepens an ebb (ebb sets WNW past the waterfront, flood ESE).
    private static func roughOutside(_ hour: WeatherHour, current: Double?) -> Bool {
        if hour.windDirection >= 315 || hour.windDirection <= 45 {
            return hour.windSpeed >= northChop
        }
        let blowsEast = hour.windDirection > 225 && hour.windDirection < 315
        let blowsWest = hour.windDirection > 45 && hour.windDirection < 135
        let opposed = current.map { ($0 < 0 && blowsEast) || ($0 > 0 && blowsWest) } ?? false
        return hour.windSpeed >= (opposed ? chopWind - opposedWindPenalty : chopWind)
    }

    private static let thunderCodes: Set<Int> = [95, 96, 99]
    private static let heavyRainCodes: Set<Int> = [65, 67, 82]

    /// The rare "don't get in at all" cases. Anything short of these is a choice of
    /// route, not a veto — the cove absorbs the rest. Each of these ran under 0.1% of
    /// daylight hours over the last year here, which is the frequency they should have.
    static func advisory(at time: Date, in forecast: [WeatherHour]) -> String? {
        guard let hour = weather(at: time, in: forecast) else { return nil }
        if thunderCodes.contains(hour.weatherCode) { return "THUNDERSTORM — STAY OUT OF THE WATER" }
        if hour.windSpeed >= galeWind { return "GALE \(Int(hour.windSpeed)) MPH — DON'T SWIM" }

        // SFPUC advises no water contact for 24–72h after a combined sewer discharge into
        // Aquatic Park, and heavy rain is what sets one off.
        // ponytail: the forecast starts at local midnight, so a dawn marker only sees a
        // few hours back — pass past_days=1 in API.weather() if that proves too short.
        let since = time.addingTimeInterval(-rainLookback * 3600)
        let discharge = forecast.contains {
            $0.time >= since && $0.time <= time && heavyRainCodes.contains($0.weatherCode)
        }
        return discharge ? "HEAVY RAIN — SEWER OVERFLOW RISK, 48H" : nil
    }

    private static func unavailable(_ name: String) -> RouteVerdict {
        RouteVerdict(title: name, sublabel: "—", verdict: "—", condition: "no data",
                     isFavorable: false)
    }

    /// `GATE 1.4 KT EBB` for the route read header (§5.7).
    static func gateSummary(velocity: Double?) -> String {
        guard let velocity else { return "GATE —" }
        if abs(velocity) <= slackThreshold { return "GATE SLACK" }
        return "GATE \(oneDecimal(abs(velocity))) KT \(velocity < 0 ? "EBB" : "FLOOD")"
    }

    // MARK: - Swim windows

    /// Only the two exposed routes get windows. The cove needs no planning — it is
    /// sheltered whatever the current is doing, which is the whole point of it.
    enum SwimRoute { case west, east }

    // Only the window grid reads these now, and `bestScore` is 0 or 1, so a window is
    // always "good".
    static let goodScore: Double = 0.55
    static let fairScore: Double = 0.25
    /// The hours a swim can start in — Lauren's own, not sunrise and sunset. The tide
    /// figure shows the same span.
    static let firstLight = 6
    static let lastLight = 20
    /// How finely the window scan steps. A window is only the 20–40 minutes of start times
    /// that satisfy the slack-then-ride rule, so it needs a fine step to be seen at all;
    /// 5 minutes is still cheap enough for a five-day scan on every refresh.
    static let scanStep: TimeInterval = 5 * 60

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = API.zone
        return calendar
    }()

    static func isDaylight(_ time: Date) -> Bool {
        let hour = calendar.component(.hour, from: time)
        return hour >= firstLight && hour < lastLight
    }

    /// Slack as the sheet reads it: the readout rounds to a tenth, so 0.54 kt shows as 0.5
    /// and counts, and 0.55 shows as 0.6 and does not.
    static func isSlack(_ velocity: Double) -> Bool {
        (abs(velocity) * 10).rounded() <= slackThreshold * 10
    }

    /// Which leg of a swim is the one in slack water.
    enum SlackLeg { case out, back }

    /// Whether a swim of `route` starting at `time` works: `outLeg` minutes out, the same
    /// back, with one of the two legs in slack water.
    ///
    /// Slack out is the Dolphin Club rule, the hard part first: the current must also be
    /// running the right way (flood for west, ebb for east) by `ridingSpeed` at the turn
    /// to carry you home. There is no ceiling on the ride home.
    ///
    /// Slack back puts the slack on the home leg instead: you ride the dying current out
    /// (ebb for west, flood for east) and swim home through the slack. The out leg is never
    /// swum against the current, not even a slack-strength one — every check of it runs your
    /// way — but has no ceiling; the caption says how hard it runs (see `window`).
    ///
    /// Every 5 minutes of the slack leg is checked, so a current that picks up mid-leg is
    /// caught. Rough wind and advisories close a window; a missing forecast does not.
    static func windowOpen(at time: Date, route: SwimRoute, slackLeg: SlackLeg,
                           samples: [CurrentSample], forecast: [WeatherHour]) -> Bool {
        guard advisory(at: time, in: forecast) == nil,
              let out = velocity(at: time, in: samples) else { return false }
        if let hour = weather(at: time, in: forecast), roughOutside(hour, current: out) {
            return false
        }
        let turn = time.addingTimeInterval(outLeg * 60)
        guard slackAll(from: slackLeg == .out ? time : turn, samples: samples) else {
            return false
        }
        // Positive for the current that carries you home: flood for west, ebb for east.
        let home: Double = route == .west ? 1 : -1
        guard slackLeg == .out else {
            return stride(from: 0.0, through: outLeg, by: 5).allSatisfy { minute in
                velocity(at: time.addingTimeInterval(minute * 60), in: samples)
                    .map { home * $0 <= 0 } ?? false
            }
        }
        return velocity(at: turn, in: samples).map { home * $0 >= ridingSpeed } ?? false
    }

    /// Slack at every 5-minute check of the `outLeg` minutes from `start`.
    private static func slackAll(from start: Date, samples: [CurrentSample]) -> Bool {
        stride(from: 0.0, through: outLeg, by: 5).allSatisfy { minute in
            velocity(at: start.addingTimeInterval(minute * 60), in: samples).map(isSlack) ?? false
        }
    }

    /// Whether `time` falls in a window the list would show: a good start, either leg in
    /// slack, inside the swimming hours. What the live route read uses, so a route is never
    /// marked GO for a window the headline leaves out.
    static func inWindow(at time: Date, route: SwimRoute,
                         samples: [CurrentSample], forecast: [WeatherHour]) -> Bool {
        isDaylight(time) && [SlackLeg.out, .back].contains {
            windowOpen(at: time, route: route, slackLeg: $0, samples: samples, forecast: forecast)
        }
    }

    /// 1 when either exposed route has a window starting at `time`, else 0 — what the
    /// window grid inks each hour with.
    static func bestScore(at time: Date, samples: [CurrentSample],
                          forecast: [WeatherHour]) -> Double {
        let open = [SwimRoute.west, .east].contains {
            inWindow(at: time, route: $0, samples: samples, forecast: forecast)
        }
        return open ? 1 : 0
    }

    /// Every daylight run of good start times from `from` to `through`, slack-out and
    /// slack-back runs found separately and merged in start order. A run can be a single
    /// start time; that is still a swim.
    static func swimWindows(route: SwimRoute, samples: [CurrentSample],
                            forecast: [WeatherHour], from: Date, through: Date) -> [SwimWindow] {
        guard through > from else { return [] }
        var windows: [SwimWindow] = []

        for leg in [SlackLeg.out, .back] {
            var runStart: Date?
            var time = from

            func close(at end: Date) {
                guard let start = runStart else { return }
                runStart = nil
                windows.append(window(start: start, end: end, slackLeg: leg, samples: samples))
            }

            while time <= through {
                let open = isDaylight(time)
                    && windowOpen(at: time, route: route, slackLeg: leg, samples: samples,
                                  forecast: forecast)
                if open, runStart == nil { runStart = time }
                if !open { close(at: time.addingTimeInterval(-scanStep)) }
                time.addTimeInterval(scanStep)
            }
            close(at: through)
        }
        return windows.sorted { $0.start < $1.start }
    }

    /// The window a swimmer would walk down for next: the one still open, or the next
    /// one to open. `windows` is one route's, in start order, from `swimWindows`.
    ///
    /// Slack out is the one to recommend: a ride-out window with a slack-out partner right
    /// behind it gives way to the partner. While the time is inside the two, the panel
    /// shows both (see `windowPair`).
    static func nextWindow(in windows: [SwimWindow], after now: Date) -> SwimWindow? {
        windows.indices.first { i in
            let window = windows[i]
            guard window.end >= now else { return false }
            return window.slackLeg == .out
                || !windows[(i + 1)...].contains { partners(window, $0) }
        }.map { windows[$0] }
    }

    /// The pair round one slack whose swims `time` falls inside: from the first ride-out
    /// start to the last slack-out finish, which is where the tide figure draws arrows.
    static func windowPair(route: SwimRoute, in windows: [SwimWindow],
                           at time: Date) -> WindowPair? {
        zip(windows, windows.dropFirst())
            .first { partners($0, $1) && $0.start <= time && time <= swimsEnd($1) }
            .map { WindowPair(route: route, ride: $0, slack: $1) }
    }

    /// The last swim out of `window` back on the beach: its last start, plus out and back.
    static func swimsEnd(_ window: SwimWindow) -> Date {
        window.end.addingTimeInterval(2 * outLeg * 60)
    }

    /// A ride-out window and a slack-out one that starts before its swims are done.
    private static func partners(_ ride: SwimWindow, _ slack: SwimWindow) -> Bool {
        ride.slackLeg == .back && slack.slackLeg == .out && slack.start <= swimsEnd(ride)
    }

    /// Captioned with the current on the leg that is not slack, taken at its strongest for
    /// a start in the middle of the window: `slack out, 0.6kt flood back`.
    private static func window(start: Date, end: Date, slackLeg: SlackLeg,
                               samples: [CurrentSample]) -> SwimWindow {
        let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        let leg = slackLeg == .out ? middle.addingTimeInterval(outLeg * 60) : middle
        let peak = stride(from: 0.0, through: outLeg, by: 5)
            .compactMap { velocity(at: leg.addingTimeInterval($0 * 60), in: samples) }
            .max { abs($0) < abs($1) } ?? 0
        let current = "\(oneDecimal(abs(peak)))kt \(peak < 0 ? "ebb" : "flood")"
        return SwimWindow(start: start, end: end,
                          caption: slackLeg == .out ? "slack out, \(current) back"
                                                    : "\(current) out, slack back",
                          slackLeg: slackLeg)
    }

    // MARK: - Clocks

    /// `11:42 am`. Lowercase because it is set in handwriting, and the faces read better
    /// lowercase at the size the caption runs at.
    static func handClock(_ time: Date) -> String {
        clock.string(from: time).lowercased()
    }

    /// `9:30 – 11:00 AM`, the window itself, or `9:30 AM` when it is a single start. Printed in Didot. The meridiem is written
    /// once when both ends share it, and after each end when the window crosses noon.
    ///
    /// Hair spaces flank the dash — without them the headline's negative tracking pulls
    /// it flush into the digits on either side and the three strokes merge into one smear.
    static func span(_ window: SwimWindow) -> String {
        if window.start == window.end { return clock.string(from: window.start) }
        let start = spanClock.string(from: window.start)
        let end = spanClock.string(from: window.end)
        let startPeriod = meridiem.string(from: window.start)
        let endPeriod = meridiem.string(from: window.end)
        let dash = "\u{200A}–\u{200A}"
        return startPeriod == endPeriod
            ? "\(start)\(dash)\(end) \(endPeriod)"
            : "\(start) \(startPeriod)\(dash)\(end) \(endPeriod)"
    }

    private static let meridiem: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "a"
        return formatter
    }()

    private static let spanClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    // MARK: - Helpers

    /// Adjacent pair surrounding `time`, plus how far between them it falls.
    /// Binary search, so it holds up if NOAA leaves a gap in the samples.
    private static func bracket<T>(_ items: [T], _ time: Date,
                                   _ key: KeyPath<T, Date>) -> (T, T, Double)? {
        guard items.count >= 2,
              time >= items[0][keyPath: key],
              time <= items[items.count - 1][keyPath: key] else { return nil }

        var low = 0, high = items.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if items[mid][keyPath: key] <= time { low = mid } else { high = mid }
        }
        let a = items[low], b = items[high]
        let span = b[keyPath: key].timeIntervalSince(a[keyPath: key])
        let fraction = span > 0 ? time.timeIntervalSince(a[keyPath: key]) / span : 0
        return (a, b, fraction)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = API.zone
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
