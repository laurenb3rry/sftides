import Foundation

enum Conditions {

    // TUNABLE — calibrate against real swims over a season. The wind numbers are set
    // off a year of hourly Open-Meteo at the cove: median 7, p90 13, p99 19 mph.
    // The current numbers are Gate knots (SFB1203 bin 18 runs to about ±3.4), which
    // read far higher than the water actually moving past Aquatic Park.
    static let slackThreshold: Double = 0.5      // knots
    static let approachWindow: Double = 60       // minutes; "wait" advice appears within this
    static let calmWind: Double = 12             // mph; above this the cove stops reading CALM
    static let chopWind: Double = 18             // mph; too rough to be outside the cove
    static let northChop: Double = 12            // mph from the north — the opening faces that way
    static let opposedWindPenalty: Double = 4    // mph off chopWind when wind fights the current
    static let galeWind: Double = 25             // mph; nobody should be getting in
    static let swimDuration: Double = 40         // minutes out and back — the leg the pick plans for
    static let ebbCeiling: Double = 2.0          // knots of ebb before the cove is the only answer
    static let floodCeiling: Double = 2.8        // knots of flood; looser, a flood fails toward the wharf
    static let rainLookback: Double = 24         // hours back to look for a discharge-triggering rain

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

    // MARK: - Gate current

    /// Interpolated between the 6-minute samples, the same way tide height is.
    static func velocity(at time: Date, in samples: [CurrentSample]) -> Double? {
        guard let (a, b, fraction) = bracket(samples, time, \.time) else { return nil }
        return a.velocity + (b.velocity - a.velocity) * fraction
    }

    static func nextSlack(after time: Date, in events: [CurrentEvent]) -> CurrentEvent? {
        events.first { $0.type == .slack && $0.time > time }
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
    /// flood runs east toward the wharf. The Dolphin Club's rule is to do the hard part
    /// first — swim out against the water and ride it home — so the pick follows the
    /// current on the *return* leg rather than the current right now. That gets the
    /// reversal right when a slack falls mid-swim: you leave into the dying current and
    /// the new one carries you back to the opening. Flooding home means go west,
    /// ebbing home means go east.
    ///
    /// When neither is safe the cove is the answer, and it nearly always is one:
    /// Municipal Pier keeps the current out of it, so only wind reaches in there.
    static func routeRead(at time: Date, samples: [CurrentSample], events: [CurrentEvent],
                          forecast: [WeatherHour]) -> (routes: [RouteVerdict], advisory: String?) {
        let now = velocity(at: time, in: samples)
        let hour = weather(at: time, in: forecast)
        let note = advisory(at: time, in: forecast)

        let leg = time.addingTimeInterval(swimDuration * 60)
        let home = velocity(at: leg, in: samples) ?? now

        let rough = roughOutside(hour, current: now)
        let tooStrong = tooStrongToSwim(now)
        let pick: Route? = note != nil ? nil
            : (rough || tooStrong) ? .cove
            : ((home ?? 0) >= 0 ? .west : .east)

        // There are only two exposed routes and they alternate, so whichever one is not
        // picked becomes the pick at the next reversal — which arrives a swim's length
        // before the slack itself, since the pick reads the return leg.
        let flip = nextSlack(after: leg, in: events)?.time
        let wait = flip.map { $0.timeIntervalSince(leg) / 60 }
        let flipTime = flip.map { clock.string(from: $0) } ?? "—"

        /// West and east differ only in their copy; everything deciding them is shared.
        func exposed(_ name: String, _ picked: Bool, ride: String, wrongWay: String,
                     withCurrent: String) -> RouteVerdict {
            guard let now else { return unavailable(name) }
            if picked {
                let slackNow = abs(home ?? 0) <= slackThreshold
                return RouteVerdict(title: name,
                                    sublabel: slackNow ? "SLACK NOW" : ride,
                                    verdict: "GO",
                                    condition: slackNow ? "slack now" : withCurrent,
                                    isFavorable: true)
            }
            if tooStrong {
                let magnitude = oneDecimal(abs(now))
                return now < 0
                    ? RouteVerdict(title: name, sublabel: "\(magnitude) KT OUTBOUND",
                                   verdict: "STRONG EBB", condition: "strong ebb",
                                   isFavorable: false)
                    : RouteVerdict(title: name, sublabel: "\(magnitude) KT INBOUND",
                                   verdict: "STRONG FLOOD", condition: "strong flood",
                                   isFavorable: false)
            }
            if rough, let hour {
                return RouteVerdict(title: name, sublabel: "WIND \(Int(hour.windSpeed)) MPH",
                                    verdict: "CHOP", condition: "chop", isFavorable: false)
            }
            if abs(home ?? 0) <= slackThreshold {
                return RouteVerdict(title: name, sublabel: "SLACK NOW",
                                    verdict: "EITHER WAY", condition: "slack now",
                                    isFavorable: false)
            }
            if let wait, wait > 0, wait <= approachWindow {
                return RouteVerdict(title: name, sublabel: "SLACK AT \(flipTime)",
                                    verdict: "WAIT \(Int(wait))M",
                                    condition: "wait \(Int(wait)) min", isFavorable: false)
            }
            return RouteVerdict(title: name, sublabel: wrongWay,
                                verdict: "NOT NOW", condition: "wrong way", isFavorable: false)
        }

        return ([
            cove(hour, picked: pick == .cove),
            exposed(westName, pick == .west,
                    ride: "FLOOD CARRIES YOU IN", wrongWay: "EBB RUNS TO THE GATE",
                    withCurrent: "with flood"),
            exposed(eastName, pick == .east,
                    ride: "EBB CARRIES YOU IN", wrongWay: "FLOOD PUSHES EAST",
                    withCurrent: "with ebb"),
        ], note)
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
            condition: calm ? "sheltered" : "wind \(Int(hour.windSpeed))",
            isFavorable: picked
        )
    }

    /// The cove opening faces north, so a northerly pushes chop straight through it even
    /// when it is light. Otherwise it takes a real blow — unless the wind is running
    /// against the current, which stands the surface up: the prevailing westerly smooths
    /// a flood and steepens an ebb (ebb sets WNW past the waterfront, flood ESE).
    ///
    /// No forecast means rough, because the cove is the safe thing to fall back to.
    private static func roughOutside(_ hour: WeatherHour?, current: Double?) -> Bool {
        guard let hour else { return true }
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

    /// True once a current exceeds what a swimmer can be expected to fight — an ebb judged
    /// against `ebbCeiling`, a flood against `floodCeiling`, whichever direction this
    /// reading runs. Shared by the live route read and the window scan so neither can call
    /// a current swimmable that the other calls too strong.
    private static func tooStrongToSwim(_ velocity: Double?) -> Bool {
        guard let velocity else { return true }
        return velocity < 0 ? -velocity > ebbCeiling : velocity > floodCeiling
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

    // TUNABLE — the line between a window and no window, on the same 0–1 scale
    // `swimScore` returns. Raise `good` and the app offers fewer, cleaner windows.
    static let goodScore: Double = 0.55
    static let fairScore: Double = 0.25
    /// ponytail: a fixed civil-daylight bracket, not real sunrise/sunset. Add
    /// `daily=sunrise,sunset` to `API.weather()` if the shoulder months read wrong.
    static let firstLight = 7
    static let lastLight = 19
    /// How finely the window scan steps. 15 minutes is well under the shortest useful
    /// window and keeps a five-day scan cheap enough to run on every refresh.
    static let scanStep: TimeInterval = 15 * 60

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = API.zone
        return calendar
    }()

    static func isDaylight(_ time: Date) -> Bool {
        let hour = calendar.component(.hour, from: time)
        return hour >= firstLight && hour < lastLight
    }

    /// How good this moment is for swimming `route`, 0 to 1.
    ///
    /// Reads the same way `routeRead` picks: the Dolphin Club rule is to do the hard
    /// part first, so the *return* leg decides whether the water carries you home. A
    /// flood home means west, an ebb home means east. On top of that, the water has to
    /// be weak enough to swim against on the way out and the surface has to be calm
    /// enough to be out there at all.
    static func swimScore(at time: Date, route: SwimRoute,
                          samples: [CurrentSample], forecast: [WeatherHour]) -> Double {
        guard advisory(at: time, in: forecast) == nil,
              let out = velocity(at: time, in: samples),
              let hour = weather(at: time, in: forecast) else { return 0 }
        let home = velocity(at: time.addingTimeInterval(swimDuration * 60), in: samples) ?? out
        if roughOutside(hour, current: out) { return 0 }
        // A current too strong to fight kills the score outright on whichever leg it
        // falls on — the outbound leg is always fought by design, so this is the guard
        // against being sent out into a flood or ebb stronger than a swimmer can make
        // headway against, not just a softer one that happens to be worth less.
        if tooStrongToSwim(out) || tooStrongToSwim(home) { return 0 }

        // Slack both ways is half credit rather than none: it is swimmable in either
        // direction, just without a free ride home.
        let carried = route == .west ? home >= 0 : home <= 0
        let direction = carried ? 1.0 : abs(home) <= slackThreshold ? 0.5 : 0
        guard direction > 0 else { return 0 }

        let ceiling = home < 0 ? ebbCeiling : floodCeiling
        let magnitude = max(0, 1 - max(abs(out), abs(home)) / ceiling)

        let span = chopWind - calmWind
        let wind = span > 0 ? max(0, 1 - max(0, hour.windSpeed - calmWind) / span) : 1

        return direction * magnitude * wind
    }

    /// The better of the two exposed routes — what the window grid and the day ribbon
    /// ink each hour with, since either one counts as a big swim.
    static func bestScore(at time: Date, samples: [CurrentSample],
                          forecast: [WeatherHour]) -> Double {
        max(swimScore(at: time, route: .west, samples: samples, forecast: forecast),
            swimScore(at: time, route: .east, samples: samples, forecast: forecast))
    }

    /// Every daylight span from `from` to `through` that clears `goodScore`.
    static func swimWindows(route: SwimRoute, samples: [CurrentSample],
                            events: [CurrentEvent], forecast: [WeatherHour],
                            from: Date, through: Date) -> [SwimWindow] {
        guard through > from else { return [] }
        var windows: [SwimWindow] = []
        var runStart: Date?
        var time = from

        func close(at end: Date) {
            guard let start = runStart else { return }
            runStart = nil
            // A single step is a rounding artefact, not a window worth walking down for.
            guard end > start else { return }
            windows.append(window(start: start, end: end, samples: samples, events: events))
        }

        while time <= through {
            let open = isDaylight(time)
                && swimScore(at: time, route: route, samples: samples,
                             forecast: forecast) >= goodScore
            if open, runStart == nil { runStart = time }
            if !open { close(at: time.addingTimeInterval(-scanStep)) }
            time.addTimeInterval(scanStep)
        }
        close(at: through)
        return windows
    }

    /// The window a swimmer would walk down for next: the one still open, or the next
    /// one to open. Scans the whole fetched range so a flat afternoon rolls to tomorrow.
    static func nextWindow(route: SwimRoute, samples: [CurrentSample],
                           events: [CurrentEvent], forecast: [WeatherHour],
                           after now: Date) -> SwimWindow? {
        guard let last = samples.last?.time else { return nil }
        return swimWindows(route: route, samples: samples, events: events, forecast: forecast,
                           from: calendar.startOfDay(for: now), through: last)
            .first { $0.end > now }
    }

    private static func window(start: Date, end: Date, samples: [CurrentSample],
                               events: [CurrentEvent]) -> SwimWindow {
        let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        // The slack inside the window is the one the window exists because of; falling
        // back to the next one keeps the caption honest when the run is cut short by
        // nightfall or the end of the data rather than by the current turning.
        let slack = events.first { $0.type == .slack && $0.time >= start && $0.time <= end }?.time
            ?? nextSlack(after: start, in: events)?.time
        return SwimWindow(start: start, end: end, slack: slack,
                          current: currentPhrase(at: middle, in: samples))
    }

    /// The line under the window time, in handwriting, so it stays short and lowercase:
    /// `ebb easing`, `flood under 1 kt`, `ebb 1.4 kt`.
    static func currentPhrase(at time: Date, in samples: [CurrentSample]) -> String {
        guard let velocity = velocity(at: time, in: samples) else { return "current unknown" }
        let name = velocity < 0 ? "ebb" : "flood"
        if abs(velocity) <= slackThreshold { return "\(name) near slack" }
        let later = self.velocity(at: time.addingTimeInterval(1800), in: samples) ?? velocity
        if abs(later) < abs(velocity) { return "\(name) easing" }
        if abs(velocity) < 1 { return "\(name) under 1 kt" }
        return "\(name) \(oneDecimal(abs(velocity))) kt"
    }

    // MARK: - Clocks

    /// `11:42 am`. Lowercase because it is set in handwriting, and the faces read better
    /// lowercase at the size the caption runs at.
    static func handClock(_ time: Date) -> String {
        clock.string(from: time).lowercased()
    }

    /// `9:30 – 11:00 AM`, the window itself. Printed in Didot. The meridiem is written
    /// once when both ends share it, and after each end when the window crosses noon.
    ///
    /// Hair spaces flank the dash — without them the headline's negative tracking pulls
    /// it flush into the digits on either side and the three strokes merge into one smear.
    static func span(_ window: SwimWindow) -> String {
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
