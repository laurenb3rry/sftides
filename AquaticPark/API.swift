import Foundation

enum APIError: LocalizedError {
    case noaa(String)
    case badValue(String)

    var errorDescription: String? {
        switch self {
        case .noaa(let message): return message
        case .badValue(let raw): return "Unparseable value: \(raw)"
        }
    }
}

enum API {
    static let tideStation = "9414290"
    static let currentStation = "SFB1203"
    static let currentBin = 18

    /// 9414290's water temperature sensor is offline (mdapi reports `status: 0`),
    /// so this reads Richmond — the nearest in-bay station with a live sensor and
    /// 99.9% uptime over the last 30 days.
    /// ponytail: in-bay proxy 8.4 mi away. Aquatic Park pulls two ways against it —
    /// colder ocean inflow at the Gate, warmer sheltered cove behind Municipal Pier.
    /// Tune `waterTempOffset` once there are enough real swim readings to calibrate.
    static let waterTempStation = "9414863"

    /// Degrees F added to the station reading. Zero until calibrated.
    static let waterTempOffset = 0.0
    static let latitude = 37.8077
    static let longitude = -122.4230

    /// Station-local time. Hardcoded rather than `.current` so the readouts stay
    /// on Aquatic Park time no matter where the phone is.
    static let zone = TimeZone(identifier: "America/Los_Angeles")!

    // MARK: - Tides

    static func tideCurve() async throws -> [TideSample] {
        let (begin, end) = dateRange()
        let url = noaaURL(station: tideStation, [
            "product": "predictions", "datum": "MLLW", "interval": "6",
            "begin_date": begin, "end_date": end,
        ])
        return try await get(url, as: PredictionsResponse.self).predictions.map {
            TideSample(time: try noaaDate($0.t), height: try number($0.v))
        }
    }

    static func tideExtremes() async throws -> [TideExtreme] {
        let (begin, end) = dateRange()
        let url = noaaURL(station: tideStation, [
            "product": "predictions", "datum": "MLLW", "interval": "hilo",
            "begin_date": begin, "end_date": end,
        ])
        return try await get(url, as: PredictionsResponse.self).predictions.compactMap { row in
            guard let raw = row.type, let type = TideExtremeType(rawValue: raw) else { return nil }
            return TideExtreme(time: try noaaDate(row.t), height: try number(row.v), type: type)
        }
    }

    /// Observed only — NOAA does not forecast water temperature (§5.4).
    static func waterTemperature() async throws -> WaterTempReading {
        let url = noaaURL(station: waterTempStation,
                          ["product": "water_temperature", "date": "latest"])
        guard let row = try await get(url, as: WaterTempResponse.self).data.first else {
            throw APIError.noaa("No water temperature reported")
        }
        return WaterTempReading(time: try noaaDate(row.t),
                                temperature: try number(row.v) + waterTempOffset)
    }

    // MARK: - Currents

    static func currents() async throws -> [CurrentEvent] {
        let (begin, end) = dateRange()
        let url = noaaURL(station: currentStation, [
            "product": "currents_predictions", "interval": "MAX_SLACK",
            "bin": String(currentBin), "begin_date": begin, "end_date": end,
        ])
        return try await get(url, as: CurrentsResponse.self).currentPredictions.cp.compactMap { row in
            guard let raw = row.type, let type = CurrentEventType(rawValue: raw) else { return nil }
            return CurrentEvent(time: try noaaDate(row.time), velocity: row.velocity, type: type)
        }
    }

    /// 6-minute velocity predictions. The slack crossings are measured off these
    /// directly rather than inferred from the MAX_SLACK extrema.
    static func currentsFine() async throws -> [CurrentSample] {
        let (begin, end) = dateRange()
        let url = noaaURL(station: currentStation, [
            "product": "currents_predictions", "interval": "6",
            "bin": String(currentBin), "begin_date": begin, "end_date": end,
        ])
        return try await get(url, as: CurrentsResponse.self).currentPredictions.cp.map { row in
            CurrentSample(time: try noaaDate(row.time), velocity: row.velocity)
        }
    }

    // MARK: - Weather

    static func weather() async throws -> [WeatherHour] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            "latitude": String(latitude),
            "longitude": String(longitude),
            "hourly": "temperature_2m,wind_speed_10m,wind_direction_10m,weather_code,uv_index",
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "timezone": zone.identifier,
            "forecast_days": "4",
        ].map(URLQueryItem.init(name:value:))

        let hourly = try await get(components.url!, as: WeatherResponse.self).hourly
        return try hourly.time.indices.compactMap { i in
            guard let air = hourly.temperature[i], let wind = hourly.windSpeed[i],
                  let direction = hourly.windDirection[i], let code = hourly.weatherCode[i]
            else { return nil }
            return WeatherHour(
                time: try openMeteoDate(hourly.time[i]),
                airTemperature: air,
                windSpeed: wind,
                windDirection: direction,
                weatherCode: code,
                uvIndex: hourly.uvIndex[i]
            )
        }
    }

    // MARK: - Request plumbing

    private static func noaaURL(station: String, _ extra: [String: String]) -> URL {
        var components = URLComponents(
            string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        let shared = [
            "station": station, "time_zone": "lst_ldt", "units": "english",
            "format": "json", "application": "AquaticParkSwim",
        ]
        components.queryItems = shared.merging(extra) { _, new in new }
            .map(URLQueryItem.init(name:value:))
        return components.url!
    }

    private static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        // NOAA answers failures with HTTP 200 and an error envelope, so check the body.
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            throw APIError.noaa(envelope.error.message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func dateRange() -> (String, String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = Date()
        let end = calendar.date(byAdding: .day, value: 3, to: today)!
        return (dayFormatter.string(from: today), dayFormatter.string(from: end))
    }

    private static func number(_ raw: String) throws -> Double {
        guard let value = Double(raw) else { throw APIError.badValue(raw) }
        return value
    }

    private static func noaaDate(_ raw: String) throws -> Date {
        guard let date = noaaFormatter.date(from: raw) else { throw APIError.badValue(raw) }
        return date
    }

    private static func openMeteoDate(_ raw: String) throws -> Date {
        guard let date = openMeteoFormatter.date(from: raw) else { throw APIError.badValue(raw) }
        return date
    }

    private static let noaaFormatter = formatter("yyyy-MM-dd HH:mm")
    private static let openMeteoFormatter = formatter("yyyy-MM-dd'T'HH:mm")
    private static let dayFormatter = formatter("yyyyMMdd")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Wire formats

private struct ErrorEnvelope: Decodable {
    struct Payload: Decodable { let message: String }
    let error: Payload
}

/// Tide values arrive as strings (`"5.709"`); the `type` field is present only for hilo.
private struct PredictionsResponse: Decodable {
    struct Row: Decodable {
        let t: String
        let v: String
        let type: String?
    }
    let predictions: [Row]
}

private struct WaterTempResponse: Decodable {
    struct Row: Decodable {
        let t: String
        let v: String
    }
    let data: [Row]
}

/// Unlike the tide products, `Velocity_Major` arrives as a JSON number, not a string.
/// `Type` is present only on MAX_SLACK rows — the 6-minute product omits it.
private struct CurrentsResponse: Decodable {
    struct Row: Decodable {
        let time: String
        let type: String?
        let velocity: Double

        enum CodingKeys: String, CodingKey {
            case time = "Time"
            case type = "Type"
            case velocity = "Velocity_Major"
        }
    }
    struct Predictions: Decodable { let cp: [Row] }
    let currentPredictions: Predictions

    enum CodingKeys: String, CodingKey {
        case currentPredictions = "current_predictions"
    }
}

private struct WeatherResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double?]
        let windSpeed: [Double?]
        let windDirection: [Double?]
        let weatherCode: [Int?]
        let uvIndex: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case weatherCode = "weather_code"
            case uvIndex = "uv_index"
        }
    }
    let hourly: Hourly
}
