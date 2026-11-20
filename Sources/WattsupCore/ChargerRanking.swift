import Foundation

/// Ranks the chargers a user has owned. The overall score weighs what each one can deliver,
/// how efficiently, and its report card; a factor not measured yet is left out, not zeroed.
public enum ChargerRanking {
    public enum Order: String, CaseIterable, Identifiable, Sendable {
        case overall = "Overall", power = "Power", efficiency = "Efficiency", quality = "Quality", recent = "Recently used"
        public var id: String { rawValue }
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var record: ChargerRecord
        /// 0 to 100, or nil while nothing about the charger has been measured
        public var score: Double?
        /// Which factors the score includes, for an honest caption
        public var measured: [String]
        public var id: String { record.fingerprint }
    }

    static let powerWeight = 0.4, efficiencyWeight = 0.3, qualityWeight = 0.3

    public static func entries(_ records: [ChargerRecord]) -> [Entry] {
        let strongest = records.compactMap(\.ceilingWatts).max() ?? 0
        return records.map { r in
            var parts: [(weight: Double, value: Double, name: String)] = []
            if let c = r.ceilingWatts, strongest > 0 { parts.append((powerWeight, c / strongest, "power")) }
            // Efficiency spans roughly 80 to 100 percent in practice, so map that range onto 0 to 1
            if let e = r.averageEfficiency { parts.append((efficiencyWeight, min(1, max(0, (e - 0.80) / 0.20)), "efficiency")) }
            if let q = r.quality { parts.append((qualityWeight, Double(q.rawValue) / 3, "quality")) }
            let total = parts.reduce(0) { $0 + $1.weight }
            let score = total > 0 ? parts.reduce(0) { $0 + $1.weight * $1.value } / total * 100 : nil
            return Entry(record: r, score: score, measured: parts.map(\.name))
        }
    }

    public static func ranked(_ records: [ChargerRecord], by order: Order) -> [Entry] {
        let list = entries(records)
        func desc<T: Comparable>(_ a: T?, _ b: T?) -> Bool? {
            switch (a, b) {
            case let (x?, y?): return x == y ? nil : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return nil
            }
        }
        return list.sorted { a, b in
            let primary: Bool?
            switch order {
            case .overall: primary = desc(a.score, b.score)
            case .power: primary = desc(a.record.ceilingWatts, b.record.ceilingWatts)
            case .efficiency: primary = desc(a.record.averageEfficiency, b.record.averageEfficiency)
            case .quality: primary = desc(a.record.quality, b.record.quality)
            case .recent: primary = desc(a.record.lastSeen, b.record.lastSeen)
            }
            // Ties fall back to the most recently used, so the order is stable and sensible
            return primary ?? (a.record.lastSeen > b.record.lastSeen)
        }
    }
}
