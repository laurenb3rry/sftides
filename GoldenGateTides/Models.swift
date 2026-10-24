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
    /// Today's lowest and highest at the sensor so far. Optional so a cache written
    /// before they were fetched still decodes.
    var low: Double?
    var high: Double?
    /// True when the buoy was unavailable and this is Richmond with a fixed correction.
    /// Optional so a cache written before it existed still decodes (as not estimated).
    var estimated: Bool?
    /// The two sensors behind `temperature`, kept so the figure can be moved with the tide
    /// (`Conditions.waterTemperature`). Optional for the same cache reason.
    var richmond: Double?
    var buoy: Double?

    var range: (low: Double, high: Double)? {
        guard let low, let high else { return nil }
        return (low, high)
    }
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

/// A run of good start times for one of the two exposed routes, with a phrase for which
/// leg is slack and what runs on the other.
struct SwimWindow: Identifiable, Equatable {
    let start: Date
    let end: Date
    /// `slack out, 0.6kt flood back` — which leg is slack, and what runs on the other.
    let caption: String
    let slackLeg: Conditions.SlackLeg
    var id: Date { start }
}

/// The two windows round one slack — ride out then slack back, and slack out then ride
/// back — whose swims run together on the tide figure.
struct WindowPair: Equatable {
    let route: Conditions.SwimRoute
    let ride: SwimWindow
    let slack: SwimWindow
}

/// Curve and extremes share a fetch and a TTL, so they cache as one payload.
struct TidePayload: Codable {
    let curve: [TideSample]
    let extremes: [TideExtreme]
}
