import Foundation

struct TideSample: Identifiable {
    let id = UUID()
    let time: Date
    let height: Double // feet, MLLW
}

enum TideExtremeType: String {
    case high = "H"
    case low = "L"
}

struct TideExtreme: Identifiable {
    let id = UUID()
    let time: Date
    let height: Double
    let type: TideExtremeType
}

struct WaterTempReading {
    let time: Date
    let temperature: Double // °F
}

enum CurrentEventType: String {
    case flood
    case ebb
    case slack
}

struct CurrentEvent: Identifiable {
    let id = UUID()
    let time: Date
    let velocity: Double // knots, signed: + flood, - ebb
    let type: CurrentEventType
}

struct SlackWindow: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let minVelocity: Double // knots
}

struct WeatherHour: Identifiable {
    let id = UUID()
    let time: Date
    let airTemperature: Double // °F
    let windSpeed: Double // mph
    let windDirection: Double // degrees
    let weatherCode: Int
    let uvIndex: Double?
}

struct RouteVerdict {
    let title: String
    let sublabel: String
    let verdict: String
    let isFavorable: Bool
}
