import Foundation

public struct PowerSample: Identifiable, Equatable, Sendable {
    public var date: Date
    public var inputWatts: Double
    public var systemWatts: Double
    public var batteryWatts: Double
    public var demandWatts: Double
    public var busVolts: Double
    public var busAmps: Double
    public var percent: Int
    public var temperatureC: Double?
    public var isExternalPower: Bool
    public var adapterFingerprint: String?
    public var id: Date { date }

    public init(_ s: PowerSnapshot) {
        date = s.date
        inputWatts = s.inputWatts ?? 0
        systemWatts = s.systemWatts
        batteryWatts = s.batteryWatts
        demandWatts = s.demandWatts
        busVolts = s.busVolts
        busAmps = s.busAmps
        percent = s.percent
        temperatureC = s.temperatureC
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
