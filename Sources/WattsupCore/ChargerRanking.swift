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

/// One physical charger: an entry, or several the user marked as the same brick.
public struct Brick: Equatable, Sendable, Identifiable {
    public var id: String
    public var members: [ChargerRecord]
    /// The members folded together for ranking: the best each one reached.
    public var combined: ChargerRecord

    public var displayName: String { combined.displayName }

    public static func group(_ records: [ChargerRecord]) -> [Brick] {
        Dictionary(grouping: records, by: \.brick).map { id, members in
            let sorted = members.sorted { ($0.ceilingWatts ?? 0) > ($1.ceilingWatts ?? 0) }
            var c = sorted.first { $0.fingerprint == id } ?? sorted[0]
            c.fingerprint = id
            c.nickname = members.first { $0.fingerprint == id }?.nickname ?? c.nickname
            // Ranked on its best cable: the most power, the best grade, the measured cable resistance
            c.ceilingWatts = members.compactMap(\.ceilingWatts).max()
            c.peakInputWatts = members.map(\.peakInputWatts).max() ?? 0
            c.peakDemandWatts = members.map(\.peakDemandWatts).max() ?? 0
            c.secondsConnected = members.reduce(0) { $0 + $1.secondsConnected }
            c.lastSeen = members.map(\.lastSeen).max() ?? c.lastSeen
            c.firstSeen = members.map(\.firstSeen).min() ?? c.firstSeen
            let totals = members.compactMap(\.efficiencyTotal), counts = members.compactMap(\.efficiencyCount)
            c.efficiencyTotal = totals.isEmpty ? nil : totals.reduce(0, +)
            c.efficiencyCount = counts.isEmpty ? nil : counts.reduce(0, +)
            c.qualityGrade = members.compactMap(\.qualityGrade).max()
            c.resistanceOhms = members.compactMap(\.resistanceOhms).min()
            return Brick(id: id, members: sorted, combined: c)
        }
    }
}

public extension ChargerRanking {
    /// Ranks physical chargers, with merged entries counted once.
    static func rankedBricks(_ records: [ChargerRecord], by order: Order) -> [(brick: Brick, entry: Entry)] {
        let bricks = Brick.group(records)
        let byID = Dictionary(uniqueKeysWithValues: bricks.map { ($0.id, $0) })
        return ranked(bricks.map(\.combined), by: order).compactMap { e in byID[e.id].map { ($0, e) } }
    }
}
