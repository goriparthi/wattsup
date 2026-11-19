import Foundation

/// One daily battery health record.
public struct HealthPoint: Codable, Equatable, Sendable, Identifiable {
    public var date: Date
    public var health: Double
    public var cycles: Int
    public var nominalCapacity: Int?
    public var id: Date { date }

    public init(date: Date, health: Double, cycles: Int, nominalCapacity: Int?) {
        self.date = date
        self.health = health
        self.cycles = cycles
        self.nominalCapacity = nominalCapacity
    }
}

/// Wear rate and a projection to 80%, the level Apple uses to recommend service. Fitted by least
/// squares so day to day noise in the controller's estimate does not swing the answer.
public struct HealthTrend: Equatable, Sendable {
    public static let serviceLevel = 0.80
    public static let minimumDays = 14.0

    public var points: [HealthPoint]
    public var perHundredCycles: Double?
    public var perMonth: Double?
    public var monthsToService: Double?

    public var isCollecting: Bool { perMonth == nil }

    public init(points: [HealthPoint]) {
        self.points = points.sorted { $0.date < $1.date }
        guard let first = self.points.first, let last = self.points.last,
              last.date.timeIntervalSince(first.date) >= Self.minimumDays * 86400 else { return }
        let days = self.points.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let health = self.points.map(\.health)
        if let perDay = Self.slope(days, health) {
            perMonth = -perDay * 30.44
            if perDay < 0, let current = health.last, current > Self.serviceLevel {
                monthsToService = (current - Self.serviceLevel) / -perDay / 30.44
            }
        }
        let cycles = self.points.map { Double($0.cycles) }
        if let lo = cycles.min(), let hi = cycles.max(), hi - lo >= 5, let perCycle = Self.slope(cycles, health) {
            perHundredCycles = -perCycle * 100
        }
    }

    /// Whether a new reading should be stored: a new UTC day, or a cycle count change.
    public static func shouldRecord(_ point: HealthPoint, after last: HealthPoint?) -> Bool {
        guard let last else { return true }
        return HistoryArchive.fileName(for: point.date) != HistoryArchive.fileName(for: last.date) || point.cycles != last.cycles
    }

    static func slope(_ x: [Double], _ y: [Double]) -> Double? {
        ChargerQuality.slope(x: x, y: y)
    }
}
