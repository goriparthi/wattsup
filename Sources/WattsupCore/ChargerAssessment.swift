import Foundation

/// Judges whether the connected charger is limiting the Mac, from measured samples only.
public struct ChargerAssessment: Equatable, Sendable {
    public enum Verdict: String, Equatable, Sendable {
        case unplugged, measuring, bottleneck, notKeepingUp, headroom
    }

    public var verdict: Verdict
    public var headline: String
    public var detail: String
    public var ceilingWatts: Double?
    public var loadNow: Double?
    public var peakLoad: Double?
    public var peakDemandWatts: Double?
    public var suggestedWatts: Int?
    public var advisories: [String]

    /// Common USB-C charger sizes, used to turn a measured demand into a shopping answer.
    public static let standardSizes = [30, 35, 45, 61, 65, 67, 70, 96, 100, 140]
    static let minimumSamples = 15
    static let saturated = 0.9

    public static func suggestedSize(forDemand watts: Double) -> Int {
        let target = watts * 1.1
        return standardSizes.first { Double($0) >= target } ?? standardSizes.last!
    }

    /// `known` is the charger log, used to recognize a named charger seen on a better cable.
    public init(snapshot s: PowerSnapshot, history: PowerHistory, known: [ChargerRecord] = [],
                window: TimeInterval = 600) {
        verdict = .measuring
        headline = ""
        detail = ""
        advisories = []

        guard s.isExternalPower, let adapter = s.adapter else {
            verdict = .unplugged
            headline = "On battery"
            detail = "Plug in a charger and Wattsup will check whether it keeps up with your Mac."
            return
        }

        let ceiling = adapter.ceilingWatts
        ceilingWatts = ceiling
        loadNow = s.chargerLoad

        let samples = history.recent(window, from: s.date)
            .filter { $0.isExternalPower && $0.adapterFingerprint == adapter.fingerprint }
        let lastMinute = samples.filter { $0.date >= s.date.addingTimeInterval(-60) }
        let peakDemand = samples.map(\.demandWatts).max() ?? s.demandWatts
        peakDemandWatts = peakDemand
        if let ceiling, ceiling > 0 {
            peakLoad = samples.map { $0.inputWatts / ceiling }.max()
        }

        let cable = Self.cableFinding(adapter, known: known)
        advisories = Self.advisories(for: s, adapter: adapter, peakDemand: peakDemand, cable: cable)

        guard let ceiling, ceiling > 0, samples.count >= Self.minimumSamples else {
            headline = "Checking this charger"
            detail = "Watching it for a moment before judging it."
            return
        }

        let medianLoad = Self.median(lastMinute.map { $0.inputWatts / ceiling })
        let medianBattery = Self.median(lastMinute.map(\.batteryWatts))
        let ceilingText = Units.watts(ceiling, digits: 0)

        if medianBattery < -0.5 {
            verdict = .notKeepingUp
            let size = Self.suggestedSize(forDemand: max(peakDemand, ceiling * 1.2))
            suggestedWatts = size
            headline = "Charger can't keep up"
            detail = "Your Mac is using more than this \(ceilingText) charger supplies, so the battery "
                + "is draining while plugged in. Use a \(size) W or larger charger."
        } else if medianLoad >= Self.saturated && peakDemand > ceiling * 0.97 {
            verdict = .bottleneck
            let size = Self.suggestedSize(forDemand: peakDemand)
            suggestedWatts = size
            let running = "Running at \(Units.percent(medianLoad)) of its \(ceilingText) limit while your Mac "
                + "asks for about \(Units.watts(peakDemand, digits: 0))."
            switch cable {
            case .provenCable(let seen):
                headline = "The cable is the bottleneck"
                detail = running + " This charger delivered \(Units.watts(seen, digits: 0)) on another cable, "
                    + "so use a 5 A cable rated 100 W or 240 W."
            case .possibleCable:
                headline = "Power is capped: check the cable"
                detail = running + " If your charger is rated above 60 W, the cable is likely the limit; "
                    + "a 5 A cable rated 100 W or 240 W unlocks more. If it is a 60 W charger, "
                    + "a \(size) W or larger one would charge faster."
            case .none:
                headline = "Charger is the bottleneck"
                detail = running + " A \(size) W or larger charger would charge faster."
            }
        } else {
            verdict = .headroom
            headline = "Charger has headroom"
            detail = "Peak load \(Units.percent(peakLoad)) of its \(ceilingText) limit. It keeps up with "
                + "what your Mac is doing."
            let lighter = Self.suggestedSize(forDemand: peakDemand)
            if Double(lighter) < ceiling * 0.75 {
                advisories.append("At this workload a lighter \(lighter) W charger would also keep up.")
            }
        }
    }

    /// What the charger log and the profile menu say about the cable.
    enum CableFinding: Equatable {
        case none
        /// Every profile stops at 3 A: a 3 A cable or a 60 W charger, indistinguishable live.
        case possibleCable
        /// The same named charger offered more on another cable, so this cable is the limit.
        case provenCable(seenWatts: Double)
    }

    static func cableFinding(_ adapter: AdapterInfo, known: [ChargerRecord]) -> CableFinding {
        guard looksCableCapped(adapter) else { return .none }
        // Only a charger that reports its own name can be recognized across cables
        if let name = adapter.name {
            let best = known.filter { $0.title == name }
                .compactMap { $0.profiles.max { $0.watts < $1.watts }?.watts }
                .max() ?? 0
            if best > 61 { return .provenCable(seenWatts: best) }
        }
        return .possibleCable
    }

    static func advisories(for s: PowerSnapshot, adapter: AdapterInfo, peakDemand: Double,
                           cable: CableFinding = .none) -> [String] {
        var notes: [String] = []
        if let active = adapter.activeProfile, let best = adapter.bestProfile, best.watts > active.watts + 1 {
            notes.append("Using the \(Units.watts(active.watts, digits: 0)) profile although the charger "
                + "offers \(Units.watts(best.watts, digits: 0)). A different cable or port may unlock it.")
        }
        switch cable {
        case .provenCable(let seen):
            notes.append("Check the cable: this charger offered \(Units.watts(seen, digits: 0)) on another cable, "
                + "but only 60 W on this one.")
        case .possibleCable:
            notes.append("Capped at 60 W. Every profile stops at 3 A, the most a standard USB-C cable carries. "
                + "If your charger is rated higher, check the cable: a 5 A cable rated 100 W or 240 W unlocks "
                + "the rest. A 60 W charger stops here on any cable.")
        case .none:
            break
        }
        if let amps = adapter.negotiatedAmps, let active = adapter.activeProfile, amps < active.amps - 0.1 {
            notes.append("Current is capped at \(Units.amps(amps)) below the profile's "
                + "\(Units.amps(active.amps)). The cable may be limiting it.")
        }
        if s.slowChargingReason != 0 {
            notes.append("macOS reports slow charging (reason code \(Self.hex(s.slowChargingReason))).")
        }
        if s.notChargingReason != 0 {
            notes.append("macOS has paused charging (reason code \(Self.hex(s.notChargingReason))), "
                + "for example to hold the battery for Optimized Charging.")
        }
        if let seconds = s.thermallyLimitedSeconds, seconds > 0 {
            notes.append("Charging was slowed by heat for \(Units.duration(minutes: max(1, seconds / 60))).")
        }
        return notes
    }

    /// Chargers offer more than 3 A only after detecting a 5 A cable, so a menu that stops
    /// at exactly 20 V and 3 A is the signature of a 3 A cable or a 60 W charger.
    public static func looksCableCapped(_ adapter: AdapterInfo) -> Bool {
        guard let best = adapter.bestProfile, !adapter.isWireless else { return false }
        let maxAmps = adapter.profiles.map(\.amps).max() ?? 0
        return abs(best.volts - 20) < 0.1 && abs(maxAmps - 3) < 0.01 && abs(best.amps - 3) < 0.01
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func hex(_ value: Int) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }
}
