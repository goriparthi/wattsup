import Foundation

/// A charger and cable report card built only from measured samples. Each check reports
/// "not enough data" until the load it needs has actually happened.
public struct ChargerQuality: Equatable, Sendable {
    public enum Grade: Int, Comparable, Sendable {
        case poor = 0, fair, good, excellent

        public var title: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            }
        }

        public var tone: MetricTone {
            switch self {
            case .excellent, .good: return .charging
            case .fair: return .draining
            case .poor: return .warning
            }
        }

        public static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Check: Equatable, Sendable, Identifiable {
        public var name: String
        public var grade: Grade?
        public var value: String
        public var detail: String
        public var id: String { name }
    }

    public var checks: [Check]

    /// The weakest measured check, since one bad link limits the whole chain.
    public var overall: Grade? { checks.compactMap(\.grade).min() }

    /// Volts per amp from a least squares fit of input voltage against current.
    public var resistanceOhms: Double?
    public var sagFraction: Double?

    // Thresholds, tuned to USB-C: a good 5 A cable and connectors total roughly 0.1 ohm.
    static let minSamples = 20
    static let minCurrentSpread = 0.8
    static let loadedFraction = 0.3

    public init(adapter: AdapterInfo, samples: [PowerSample], dropouts: Int, thermallyLimitedSeconds: Int?) {
        let ceiling = adapter.ceilingWatts ?? 0
        let ours = samples.filter { $0.isExternalPower && $0.adapterFingerprint == adapter.fingerprint && $0.busAmps > 0.05 }
        var checks: [Check] = []

        // Voltage sag under load
        let loaded = ours.filter { ceiling > 0 && $0.inputWatts / ceiling >= Self.loadedFraction }
        if let nominal = adapter.negotiatedVolts, nominal > 0, loaded.count >= Self.minSamples / 2 {
            let sag = max(0, (nominal - Self.median(loaded.map(\.busVolts))) / nominal)
            sagFraction = sag
            let grade: Grade = sag <= 0.03 ? .excellent : sag <= 0.05 ? .good : sag <= 0.08 ? .fair : .poor
            checks.append(Check(name: "Voltage under load", grade: grade, value: Units.percent(sag, digits: 1) + " sag",
                                detail: "\(Units.volts(Self.median(loaded.map(\.busVolts)))) measured on a \(Units.volts(nominal, digits: 1)) profile"))
        } else {
            checks.append(Check(name: "Voltage under load", grade: nil, value: "Not enough load yet",
                                detail: "Needs the charger above \(Units.percent(Self.loadedFraction)) of its limit for a while"))
        }

        // Cable and connector resistance from the slope of volts against amps
        let amps = ours.map(\.busAmps), volts = ours.map(\.busVolts)
        if ours.count >= Self.minSamples, let lo = amps.min(), let hi = amps.max(), hi - lo >= Self.minCurrentSpread,
           let slope = Self.slope(x: amps, y: volts) {
            let ohms = max(0, -slope)
            resistanceOhms = ohms
            let grade: Grade = ohms <= 0.15 ? .excellent : ohms <= 0.25 ? .good : ohms <= 0.4 ? .fair : .poor
            let atPeak = ohms * hi * hi
            checks.append(Check(name: "Cable resistance", grade: grade, value: String(format: "%.2f Ω", ohms),
                                detail: "About \(Units.watts(atPeak)) lost in the cable at \(Units.amps(hi))"))
        } else {
            checks.append(Check(name: "Cable resistance", grade: nil, value: "Not enough variation yet",
                                detail: "Needs the current to swing by \(Units.amps(Self.minCurrentSpread, digits: 1)) or more"))
        }

        // Did it reach its limit when the Mac asked for more?
        let pushed = ours.filter { ceiling > 0 && $0.demandWatts > ceiling }
        if !pushed.isEmpty, let peak = pushed.map(\.inputWatts).max() {
            let reached = peak / ceiling
            let grade: Grade = reached >= 0.9 ? .excellent : reached >= 0.85 ? .good : reached >= 0.75 ? .fair : .poor
            checks.append(Check(name: "Delivers its rating", grade: grade, value: Units.percent(reached) + " of limit",
                                detail: "Peaked at \(Units.watts(peak)) of \(Units.watts(ceiling, digits: 0)) when the Mac wanted more"))
        } else {
            checks.append(Check(name: "Delivers its rating", grade: nil, value: "Not pushed yet",
                                detail: "Judged once the Mac asks for more than the charger's limit"))
        }

        let dropGrade: Grade = dropouts == 0 ? .excellent : dropouts <= 1 ? .good : dropouts <= 3 ? .fair : .poor
        checks.append(Check(name: "Connection", grade: dropGrade,
                            value: dropouts == 0 ? "No drop-outs" : "\(dropouts) drop-out\(dropouts == 1 ? "" : "s")",
                            detail: "Brief disconnects while plugged in, often a worn cable or loose port"))

        let hot = (thermallyLimitedSeconds ?? 0) > 0
        checks.append(Check(name: "Heat", grade: hot ? .fair : .excellent,
                            value: hot ? "Throttled" : "No throttling",
                            detail: hot ? "macOS slowed charging because of heat" : "macOS has not slowed charging for heat"))
        self.checks = checks
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 0 ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    /// Least squares slope of y on x; nil when x does not vary.
    static func slope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 1 else { return nil }
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for i in x.indices { sxy += (x[i] - mx) * (y[i] - my); sxx += (x[i] - mx) * (x[i] - mx) }
        return sxx > 1e-9 ? sxy / sxx : nil
    }
}
