import Foundation

enum Conditions {

    // TUNABLE — calibrate against real swims over a season
    static let slackThreshold: Double = 0.5      // knots
    static let approachWindow: Double = 60       // minutes; "wait" advice appears within this
    static let calmWind: Double = 10             // mph
    static let chopWind: Double = 18             // mph

    // MARK: - Chart window (§5.3)

    /// Local midnight today to local midnight +3 days. Now is not centred — it sits
    /// wherever it falls in today.
    static func chartWindow(now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = API.zone
        let start = calendar.startOfDay(for: now)
        return (start, calendar.date(byAdding: .day, value: 3, to: start)!)
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

    /// Returns the three routes in fixed order: Cove, West to Fort Mason, East to the wharf.
    /// Any input being nil yields `—` verdicts rather than a guessed reading.
    static func routeRead(velocity: Double?, nextSlack: Date?,
                          from time: Date, wind: Double?) -> [RouteVerdict] {
        let minutesToSlack = nextSlack.map { $0.timeIntervalSince(time) / 60 }
        let slackTime = nextSlack.map { clock.string(from: $0) } ?? "—"
        return [
            cove(wind: wind),
            west(velocity, minutesToSlack, slackTime),
            east(velocity, slackTime),
        ]
    }

    /// Sheltered from the current behind Municipal Pier, so wind-driven only.
    private static func cove(wind: Double?) -> RouteVerdict {
        guard let wind else { return unavailable("Cove") }
        if wind < calmWind {
            return RouteVerdict(title: "Cove", sublabel: "SHELTERED ALL DAY",
                                verdict: "CALM", isFavorable: true)
        }
        let gust = "WIND \(Int(wind)) MPH"
        return RouteVerdict(title: "Cove", sublabel: gust,
                            verdict: wind < chopWind ? "CHOP" : "WINDY", isFavorable: false)
    }

    /// The exposed one — current is the binding constraint.
    private static func west(_ velocity: Double?, _ minutesToSlack: Double?,
                             _ slackTime: String) -> RouteVerdict {
        let name = "West to Fort Mason"
        guard let velocity else { return unavailable(name) }

        if abs(velocity) <= slackThreshold {
            return RouteVerdict(title: name, sublabel: "SLACK NOW",
                                verdict: "GO", isFavorable: true)
        }
        if let minutes = minutesToSlack, minutes <= approachWindow {
            return RouteVerdict(title: name, sublabel: "SLACK AT \(slackTime)",
                                verdict: "WAIT \(Int(minutes))M", isFavorable: false)
        }
        let magnitude = oneDecimal(abs(velocity))
        return velocity < 0
            ? RouteVerdict(title: name, sublabel: "\(magnitude) KT OUTBOUND",
                           verdict: "STRONG EBB", isFavorable: false)
            : RouteVerdict(title: name, sublabel: "\(magnitude) KT INBOUND",
                           verdict: "STRONG FLOOD", isFavorable: false)
    }

    /// An ebb pulls water west toward the Gate, so swimming out east on an ebb
    /// means fighting the way back.
    private static func east(_ velocity: Double?, _ slackTime: String) -> RouteVerdict {
        let name = "East to the wharf"
        guard let velocity else { return unavailable(name) }

        if abs(velocity) <= slackThreshold {
            return RouteVerdict(title: name, sublabel: "SLACK NOW",
                                verdict: "EITHER WAY", isFavorable: true)
        }
        return velocity < 0
            ? RouteVerdict(title: name, sublabel: "EBB UNTIL \(slackTime)",
                           verdict: "EBB OUT", isFavorable: false)
            : RouteVerdict(title: name, sublabel: "FLOOD UNTIL \(slackTime)",
                           verdict: "PUSH EAST", isFavorable: false)
    }

    private static func unavailable(_ name: String) -> RouteVerdict {
        RouteVerdict(title: name, sublabel: "—", verdict: "—", isFavorable: false)
    }

    /// `GATE 1.4 KT EBB` for the route read header (§5.7).
    static func gateSummary(velocity: Double?) -> String {
        guard let velocity else { return "GATE —" }
        if abs(velocity) <= slackThreshold { return "GATE SLACK" }
        return "GATE \(oneDecimal(abs(velocity))) KT \(velocity < 0 ? "EBB" : "FLOOD")"
    }

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
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
