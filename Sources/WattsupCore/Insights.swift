import Foundation

/// Which charger to pack: the smallest one that covers how hard this Mac is actually pushed.
public struct PackAdvice: Equatable, Sendable {
    public var typicalWatts: Double
    public var heavyWatts: Double
    public var keepsUp: Brick?
    public var fastest: Brick?
    public var sampleHours: Double

    public static let minimumHours = 1.0

    /// `samples` are stored minutes; only time on a charger counts. Heavy use is the 95th percentile.
    public init?(samples: [PowerSample], bricks: [Brick]) {
        let plugged = samples.filter { $0.isExternalPower && $0.seconds > 0 }
        let hours = plugged.reduce(0) { $0 + $1.seconds } / 3600
        guard hours >= Self.minimumHours, !bricks.isEmpty else { return nil }
        let demand = plugged.map(\.demandWatts).sorted()
        typicalWatts = demand[demand.count / 2]
        heavyWatts = demand[min(demand.count - 1, Int(Double(demand.count) * 0.95))]
        sampleHours = hours
        let rated = bricks.filter { $0.combined.ceilingWatts != nil }
        keepsUp = rated.filter { ($0.combined.ceilingWatts ?? 0) >= heavyWatts }
            .min { ($0.combined.ceilingWatts ?? 0) < ($1.combined.ceilingWatts ?? 0) }
        fastest = rated.max { ($0.combined.ceilingWatts ?? 0) < ($1.combined.ceilingWatts ?? 0) }
    }

    public var headline: String {
        if let k = keepsUp { return "Pack \(k.displayName)" }
        return "None of your chargers covers your heavy use"
    }

    public var detail: String {
        let use = String(format: "Your Mac typically asks for %.0f W on a charger and %.0f W when busy.", typicalWatts, heavyWatts)
        if let k = keepsUp {
            var s = use + " \(k.displayName) (\(Units.watts(k.combined.ceilingWatts, digits: 0))) is the smallest of yours that keeps up."
            if let f = fastest, f.id != k.id {
                s += " For the fastest charge, take \(f.displayName) (\(Units.watts(f.combined.ceilingWatts, digits: 0)))."
            }
            return s
        }
        let size = ChargerAssessment.suggestedSize(forDemand: heavyWatts)
        return use + " A \(size) W or larger charger would keep up."
    }
}

/// Habits that wear a battery, measured from Wattsup's own history while it was running.
public struct BatteryCare: Equatable, Sendable {
    public var coveredHours: Double
    public var highChargeHours: Double
    public var hotHours: Double
    public var deepDischarges: Int
    public var cyclesPerWeek: Double?
    public var tips: [String]

    public static let highCharge = 95, deep = 10
    public static let hotC = 40.0
    public static let projectionHours = 24.0

    public init?(samples: [PowerSample]) {
        let s = samples.filter { $0.seconds > 0 }.sorted { $0.date < $1.date }
        let hours = s.reduce(0) { $0 + $1.seconds } / 3600
        guard hours >= 1 else { return nil }
        coveredHours = hours
        highChargeHours = s.filter { $0.isExternalPower && $0.percent >= Self.highCharge }.reduce(0) { $0 + $1.seconds } / 3600
        hotHours = s.filter { ($0.temperatureC ?? 0) >= Self.hotC }.reduce(0) { $0 + $1.seconds } / 3600
        // A deep discharge is each time the level falls below 10% after being above it
        var deepCount = 0, wasAbove = true, drained = 0.0
        for (i, p) in s.enumerated() {
            if p.percent < Self.deep && wasAbove { deepCount += 1 }
            wasAbove = p.percent >= Self.deep
            if i > 0, p.percent < s[i - 1].percent { drained += Double(s[i - 1].percent - p.percent) }
        }
        deepDischarges = deepCount
        let span = (s.last!.date.timeIntervalSince(s.first!.date)) / (7 * 86400)
        cyclesPerWeek = span >= 1 ? drained / 100 / span : nil

        var tips: [String] = []
        // Weekly figures are projected, so they wait for a day of history to mean something
        let perWeek = 7 * 24 / max(hours, 1)
        if hours < Self.projectionHours {
            tips.append(String(format: "Weekly habits appear after a day of history; %.0f hours so far.", hours))
        } else if highChargeHours * perWeek >= 20 {
            tips.append(String(format: "About %.0f hours a week plugged in above 95%%. Turning on a charge limit or Optimized Battery Charging in Battery settings slows wear.", highChargeHours * perWeek))
        }
        if hotHours >= 1 {
            tips.append(String(format: "%.0f hours at %.0f °C or hotter. Heat ages a battery fastest; keep vents clear and avoid charging in a hot bag.", hotHours, Self.hotC))
        }
        if deepDischarges > 0 {
            tips.append("Ran below \(Self.deep)% \(deepDischarges) time\(deepDischarges == 1 ? "" : "s"). Charging a little earlier is gentler on the cells.")
        }
        if tips.isEmpty { tips.append("No wear habits stand out. Moderate charge, moderate heat: exactly what a battery likes.") }
        self.tips = tips
    }
}
