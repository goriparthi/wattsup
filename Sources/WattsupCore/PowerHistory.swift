import Foundation

public struct PowerSample: Identifiable, Equatable, Codable, Sendable {
    public var date: Date
    public var inputWatts: Double
    /// Charger input plus its loss; equals input when there is no loss figure.
    public var wallWatts: Double = 0
    /// Seconds this sample stands for: 0 for a live reading, about 60 for a stored minute.
    public var seconds: Double = 0
    public var systemWatts: Double
    public var batteryWatts: Double
    public var demandWatts: Double
    public var busVolts: Double
    public var busAmps: Double
    public var percent: Int
    public var temperatureC: Double?
    public var cpuTempC: Double?
    public var fanRPM: Double?
    public var isExternalPower: Bool
    public var adapterFingerprint: String?
    public var id: Date { date }

    public init(_ s: PowerSnapshot) {
        date = s.date
        inputWatts = s.inputWatts ?? 0
        wallWatts = s.wallWatts ?? (s.inputWatts ?? 0)
        systemWatts = s.systemWatts
        batteryWatts = s.batteryWatts
        demandWatts = s.demandWatts
        busVolts = s.busVolts
        busAmps = s.busAmps
        percent = s.percent
        temperatureC = s.temperatureC
        cpuTempC = s.thermals?.cpuC
        fanRPM = s.thermals?.fanRPM
        isExternalPower = s.isExternalPower
        adapterFingerprint = s.adapter?.fingerprint
    }
}

/// Rolling in-memory window of samples for the charts and the charger check.
public struct PowerHistory: Sendable {
    public private(set) var samples: [PowerSample] = []
    public let window: TimeInterval

    public init(window: TimeInterval = 3600) {
        self.window = window
    }

    public mutating func append(_ snapshot: PowerSnapshot) {
        // A clock that jumped backwards would leave the window unsorted
        if let last = samples.last, snapshot.date < last.date { samples.removeAll() }
        samples.append(PowerSample(snapshot))
        let cutoff = snapshot.date.addingTimeInterval(-window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    public func recent(_ seconds: TimeInterval, from now: Date? = nil) -> [PowerSample] {
        guard let end = now ?? samples.last?.date else { return [] }
        let start = end.addingTimeInterval(-seconds)
        return samples.filter { $0.date >= start && $0.date <= end }
    }
}

public extension Array where Element == PowerSample {
    /// Evenly thins a series so charts stay cheap however long the window grows.
    func thinned(to limit: Int) -> [PowerSample] {
        guard count > limit, limit > 1 else { return self }
        let step = Double(count - 1) / Double(limit - 1)
        return (0..<limit).map { self[Int((Double($0) * step).rounded())] }
    }
}

/// Folds live samples into one averaged sample per minute for the on disk archive.
public struct MinuteAggregator: Sendable {
    private var bucket: [PowerSample] = []
    private var minute: Int?

    public init() {}

    /// Adds a sample; returns the finished minute when this sample starts a new one.
    public mutating func add(_ s: PowerSample) -> PowerSample? {
        let m = Int(s.date.timeIntervalSince1970 / 60)
        defer { if minute != m { minute = m; bucket = [] }; bucket.append(s) }
        guard let current = minute, current != m, !bucket.isEmpty else { return nil }
        return Self.average(bucket, minute: current)
    }

    /// The partial minute, for saving on quit.
    public func pending() -> PowerSample? {
        guard let minute, !bucket.isEmpty else { return nil }
        return Self.average(bucket, minute: minute)
    }

    static func average(_ b: [PowerSample], minute: Int) -> PowerSample {
        func mean(_ k: KeyPath<PowerSample, Double>) -> Double { b.map { $0[keyPath: k] }.reduce(0, +) / Double(b.count) }
        var out = b.last!
        out.date = Date(timeIntervalSince1970: Double(minute) * 60)
        out.inputWatts = mean(\.inputWatts)
        out.wallWatts = mean(\.wallWatts)
        out.systemWatts = mean(\.systemWatts)
        out.batteryWatts = mean(\.batteryWatts)
        out.demandWatts = mean(\.demandWatts)
        out.busVolts = mean(\.busVolts)
        out.busAmps = mean(\.busAmps)
        let temps = b.compactMap(\.temperatureC)
        out.temperatureC = temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count)
        let cpu = b.compactMap(\.cpuTempC), fans = b.compactMap(\.fanRPM)
        out.cpuTempC = cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count)
        out.fanRPM = fans.isEmpty ? nil : fans.reduce(0, +) / Double(fans.count)
        // Covered time is the span of the readings, at most a minute
        let span = (b.last!.date.timeIntervalSince(b.first!.date)) + 2
        out.seconds = min(60, max(2, span))
        out.isExternalPower = b.filter(\.isExternalPower).count * 2 >= b.count
        return out
    }
}

/// One JSON line per stored minute, a file per UTC day.
public enum HistoryArchive {
    public static func fileName(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.jsonl", c.year!, c.month!, c.day!)
    }

    public static func encode(_ s: PowerSample) -> Data? {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        guard var data = try? e.encode(s) else { return nil }
        data.append(0x0A)
        return data
    }

    /// Skips lines that do not parse, so one torn write never loses a whole day.
    public static func decode(_ data: Data) -> [PowerSample] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return data.split(separator: 0x0A).compactMap { try? d.decode(PowerSample.self, from: Data($0)) }
    }

    /// Day files older than `days`, by name, for pruning.
    public static func expired(_ names: [String], now: Date, days: Int) -> [String] {
        let cutoff = fileName(for: now.addingTimeInterval(-Double(days) * 86400))
        return names.filter { $0.hasSuffix(".jsonl") && $0 < cutoff }
    }
}
