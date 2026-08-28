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
    let start: Date
    let end: Date
    var id: Date { start }
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
    let isFavorable: Bool
}

/// Curve and extremes share a fetch and a TTL, so they cache as one payload.
struct TidePayload: Codable {
    let curve: [TideSample]
    let extremes: [TideExtreme]
}
