import Foundation

// Exactly one route must be favourable at every minute of a synthetic tidal day, and
// it must be the one you can swim home in. Run with:
//   swiftc -o /tmp/route-check AquaticPark/Models.swift AquaticPark/Conditions.swift \
//       AquaticPark/API.swift scripts/route-check.swift && /tmp/route-check

@main
struct RouteCheck {

    /// Half a sine cycle every 6h13m, peaking near the Gate's real ±3 kt.
    static func day(peak: Double = 3.0, wind: Double = 6, direction: Double = 270,
                    code: Int = 0) -> ([CurrentSample], [CurrentEvent], [WeatherHour]) {
        let start = Date(timeIntervalSince1970: 1_757_462_400)   // local midnight
        let period = 6.216 * 3600.0
        let velocity = { (t: Double) in peak * sin(.pi * t / period) }

        let samples = stride(from: 0.0, to: 48 * 3600, by: 360).map {
            CurrentSample(time: start.addingTimeInterval($0), velocity: velocity($0))
        }
        let events = stride(from: 0.0, to: 48 * 3600, by: period / 2).map { t -> CurrentEvent in
            let v = velocity(t)
            return CurrentEvent(time: start.addingTimeInterval(t), velocity: v,
                                type: abs(v) < 0.05 ? .slack : (v > 0 ? .flood : .ebb))
        }
        let hours = stride(from: 0.0, to: 48 * 3600, by: 3600).map {
            WeatherHour(time: start.addingTimeInterval($0), airTemperature: 60,
                        windSpeed: wind, windDirection: direction, weatherCode: code,
                        uvIndex: 0)
        }
        return (samples, events, hours)
    }

    static func main() {
        let start = Date(timeIntervalSince1970: 1_757_462_400)
        let swim = Conditions.swimDuration * 60

        // 1. Calm, moderate tide: exactly one blue at every minute, and never the cove.
        var (samples, events, hours) = day(peak: 1.6)
        var picks: Set<String> = []
        for minute in stride(from: 0.0, to: 24 * 60, by: 1) {
            let at = start.addingTimeInterval(minute * 60)
            let read = Conditions.routeRead(at: at, samples: samples, events: events,
                                            forecast: hours)
            let blue = read.routes.filter(\.isFavorable)
            precondition(read.advisory == nil, "calm day should carry no advisory")
            precondition(blue.count == 1, "\(blue.count) blue at minute \(minute)")
            picks.insert(blue[0].title)

            // The pick is the one the current brings you home on.
            let home = Conditions.velocity(at: at.addingTimeInterval(swim), in: samples)!
            precondition(blue[0].title.hasPrefix(home >= 0 ? "West" : "East"),
                         "wrong way at minute \(minute): home \(home), picked \(blue[0].title)")
        }
        precondition(picks == ["West to Fort Mason", "East to the wharf"],
                     "a calm moderate day should use both exposed routes: \(picks)")

        // 2. A big ebb pins you in the cove.
        (samples, events, hours) = day(peak: 3.2)
        let floodPeak = start.addingTimeInterval(3.108 * 3600)
        let ebbPeak = start.addingTimeInterval(3 * 3.108 * 3600)
        precondition(Conditions.velocity(at: ebbPeak, in: samples)! < -Conditions.ebbCeiling)
        precondition(Conditions.routeRead(at: ebbPeak, samples: samples, events: events,
                                          forecast: hours)
            .routes.first(where: \.isFavorable)?.title == "Cove", "peak ebb should be cove only")

        // 3. Wind: a light northerly closes the opening whatever the tide is doing, and
        //    a westerly of the same speed only does so when it is fighting an ebb.
        for (direction, at, expectCove) in [(0.0, floodPeak, true),
                                            (270.0, floodPeak, false),
                                            (270.0, ebbPeak, true)] as [(Double, Date, Bool)] {
            let (s, e, h) = day(peak: 1.2, wind: 14, direction: direction)
            let picked = Conditions.routeRead(at: at, samples: s, events: e, forecast: h)
                .routes.first(where: \.isFavorable)?.title
            precondition((picked == "Cove") == expectCove,
                         "14 mph from \(direction) picked \(picked ?? "nothing")")
        }

        // 4. Advisories veto every route.
        for (wind, code) in [(6.0, 95), (30.0, 0), (6.0, 65)] as [(Double, Int)] {
            let (s, e, h) = day(peak: 1.2, wind: wind, code: code)
            let read = Conditions.routeRead(at: floodPeak, samples: s, events: e, forecast: h)
            precondition(read.advisory != nil, "wind \(wind) code \(code) should advise against swimming")
            precondition(!read.routes.contains(where: \.isFavorable),
                         "nothing is blue while an advisory stands")
        }

        // 5. No data at all still leaves the cove standing.
        let bare = Conditions.routeRead(at: floodPeak, samples: [], events: [], forecast: [])
        precondition(bare.routes.first(where: \.isFavorable)?.title == "Cove",
                     "cove is the failsafe when every feed is empty")

        // 6. Windows are well formed: inside daylight, above the bar end to end,
        //    ordered, and never overlapping. This is what the headline, the ribbon and
        //    the grid all read, so a malformed one shows up in three places at once.
        (samples, events, hours) = day(peak: 1.6)
        let scanFrom = Conditions.calendar.startOfDay(for: start)
        let scanTo = scanFrom.addingTimeInterval(36 * 3600)
        var found = 0
        for route in [Conditions.SwimRoute.west, .east] {
            let windows = Conditions.swimWindows(route: route, samples: samples,
                                                 events: events, forecast: hours,
                                                 from: scanFrom, through: scanTo)
            found += windows.count
            var previousEnd: Date?
            for window in windows {
                precondition(window.end > window.start, "empty window \(window.start)")
                precondition(previousEnd.map { window.start > $0 } ?? true,
                             "windows overlap at \(window.start)")
                previousEnd = window.end
                var at = window.start
                while at <= window.end {
                    precondition(Conditions.isDaylight(at), "window runs into the dark")
                    precondition(Conditions.swimScore(at: at, route: route, samples: samples,
                                                      forecast: hours) >= Conditions.goodScore,
                                 "window dips below the bar at \(at)")
                    at.addTimeInterval(Conditions.scanStep)
                }
                precondition(!window.current.isEmpty)
            }
        }
        precondition(found > 0, "a calm moderate day should open at least one window")

        // 7. `nextWindow` picks the earliest window still open, not merely the first one
        //    in the day — standing in one must not roll you to the next.
        for route in [Conditions.SwimRoute.west, .east] {
            let all = Conditions.swimWindows(route: route, samples: samples, events: events,
                                             forecast: hours, from: scanFrom, through: scanTo)
            for probe in stride(from: 0.0, to: 30 * 3600, by: 1800) {
                let at = scanFrom.addingTimeInterval(probe)
                let next = Conditions.nextWindow(route: route, samples: samples,
                                                 events: events, forecast: hours, after: at)
                let expected = all.first { $0.end > at }
                precondition(next?.start == expected?.start,
                             "nextWindow disagrees with the scan at \(at)")
            }
        }

        // 8. An advisory closes both routes, so it must close every window with them.
        let (gs, ge, gh) = day(peak: 1.2, wind: 30)
        for route in [Conditions.SwimRoute.west, .east] {
            precondition(Conditions.swimWindows(route: route, samples: gs, events: ge,
                                                forecast: gh, from: scanFrom,
                                                through: scanTo).isEmpty,
                         "a gale should leave no windows")
        }
        precondition(Conditions.bestScore(at: floodPeak, samples: gs, forecast: gh) == 0)
        precondition(Conditions.nextWindow(route: .west, samples: [], events: [],
                                           forecast: [], after: start) == nil,
                     "no samples means no window to offer")

        // 9. Every clock on the sheet is 12-hour with am/pm, handwritten or printed.
        //    The printed span writes the meridiem once when both ends share it.
        let noon = Conditions.calendar.date(bySettingHour: 13, minute: 5, second: 0,
                                            of: start)!
        precondition(Conditions.handClock(noon) == "1:05 pm", Conditions.handClock(noon))
        precondition(Conditions.span(SwimWindow(start: noon, end: noon, slack: nil,
                                                current: "")) == "1:05–1:05 PM")
        let crossesNoon = Conditions.calendar.date(bySettingHour: 11, minute: 30, second: 0,
                                                    of: start)!
        precondition(Conditions.span(SwimWindow(start: crossesNoon, end: noon, slack: nil,
                                                current: "")) == "11:30 AM–1:05 PM")

        print("route-check: ok")
    }
}
