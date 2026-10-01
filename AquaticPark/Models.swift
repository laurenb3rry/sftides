import Foundation

// Identity is the event time rather than a fresh UUID so that rows keep their
// identity across a refresh instead of being rebuilt on every decode.

struct TideSample: Codable, Identifiable {
    let time: Date
    let height: Double // feet, MLLW
    var id: Date { time }
}

enum TideExtremeType: String, Codable {
    case high = "H"
    case low = "L"
}

struct TideExtreme: Codable, Identifiable {
    let time: Date
    let height: Double
    let type: TideExtremeType
    var id: Date { time }
}

struct WaterTempReading: Codable {
    let time: Date
    let temperature: Double // °F
}

enum CurrentEventType: String, Codable {
    case flood
    case ebb
    case slack
}

struct CurrentEvent: Codable, Identifiable {
    let time: Date
    let velocity: Double // knots, signed: + flood, - ebb
    let type: CurrentEventType
    var id: Date { time }
}

struct SlackWindow: Identifiable {
    /// NOAA's labelled slack. The window around it can start well before a high or low
    /// on a weak-current day, so ordering against tides has to use this, not `start`.
    let time: Date
    let start: Date
    let end: Date
    var id: Date { time }
}

/// A 6-minute current prediction. Unlike `CurrentEvent` these are plain samples;
/// the fine-grained product carries no flood/ebb/slack label.
struct CurrentSample: Codable, Identifiable {
    let time: Date
    let velocity: Double // knots, signed: + flood, - ebb
    var id: Date { time }
}

struct WeatherHour: Codable, Identifiable {
    let time: Date
    let airTemperature: Double // °F
    let windSpeed: Double // mph
    let windDirection: Double // degrees
    let weatherCode: Int
    let uvIndex: Double?
    var id: Date { time }
}

struct RouteVerdict {
    let title: String
    let sublabel: String
    let verdict: String
    /// Short and lowercase, because it is the one set in Lauren's handwriting.
    let condition: String
    let isFavorable: Bool
}

/// A span where one of the two exposed routes reads favourably, with the slack it hangs
/// off and a phrase for what the current is doing through it.
struct SwimWindow: Identifiable {
    let start: Date
    let end: Date
    let slack: Date?
    let current: String
    var id: Date { start }
}

/// Curve and extremes share a fetch and a TTL, so they cache as one payload.
struct TidePayload: Codable {
    let curve: [TideSample]
    let extremes: [TideExtreme]
}
