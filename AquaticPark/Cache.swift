import Foundation

/// A cached payload plus the moment it was fetched.
struct Entry<T: Codable & Sendable>: Codable, Sendable {
    var storedAt: Date
    var value: T

    init(_ value: T, storedAt: Date = Date()) {
        self.value = value
        self.storedAt = storedAt
    }

    func isFresh(_ ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(storedAt) < ttl
    }
}

struct CacheFile: Codable, Sendable {
    var tides: Entry<TidePayload>?
    var currents: Entry<[CurrentEvent]>?
    var currentsFine: Entry<[CurrentSample]>?
    var weather: Entry<[WeatherHour]>?
    var waterTemp: Entry<WaterTempReading>?

    enum TTL {
        static let tides: TimeInterval = 12 * 3600
        static let currents: TimeInterval = 12 * 3600
        static let weather: TimeInterval = 30 * 60
        static let waterTemp: TimeInterval = 15 * 60
    }
}

/// Single JSON file in Application Support holding the last successful payload
/// per source. Reads are served from memory once loaded.
actor Cache {
    static let shared = Cache()

    private var file = CacheFile()
    private var loaded = false

    private let url: URL = {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AquaticPark", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cache.json")
    }()

    /// Reads from disk on first call; afterwards returns the in-memory copy.
    @discardableResult
    func load() -> CacheFile {
        guard !loaded else { return file }
        loaded = true
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CacheFile.self, from: data) {
            file = decoded
        }
        return file
    }

    /// Mutates the cache and writes it straight back to disk.
    @discardableResult
    func update(_ mutate: @Sendable (inout CacheFile) -> Void) -> CacheFile {
        load()
        mutate(&file)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: .atomic)
        }
        return file
    }
}

extension CacheFile {
    /// When the oldest payload on screen was fetched, and whether anything is
    /// missing or past its TTL. Drives the §5.8 banner: a failed refresh is only
    /// worth mentioning once the cache can no longer cover it.
    var freshness: (oldest: Date?, stale: Bool) {
        let entries: [(storedAt: Date, fresh: Bool)] = [
            tides.map { ($0.storedAt, $0.isFresh(TTL.tides)) },
            currents.map { ($0.storedAt, $0.isFresh(TTL.currents)) },
            currentsFine.map { ($0.storedAt, $0.isFresh(TTL.currents)) },
            weather.map { ($0.storedAt, $0.isFresh(TTL.weather)) },
            waterTemp.map { ($0.storedAt, $0.isFresh(TTL.waterTemp)) },
        ].compactMap { $0 }
        return (entries.map(\.storedAt).min(),
                entries.count < 5 || entries.contains { !$0.fresh })
    }
}
