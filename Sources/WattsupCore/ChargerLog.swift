import Foundation

/// What Wattsup remembers about one charger, so travelers can compare the bricks they use.
public struct ChargerRecord: Codable, Equatable, Identifiable, Sendable {
    public var fingerprint: String
    public var title: String
    public var ratedWatts: Int?
    public var ceilingWatts: Double?
    public var profiles: [PDProfile]
    public var firstSeen: Date
    public var lastSeen: Date
    public var secondsConnected: TimeInterval
    public var peakInputWatts: Double
    public var peakDemandWatts: Double
    public var lastVerdict: String?
    /// Running efficiency average over rated readings; optional so older logs still decode.
    public var efficiencyTotal: Double?
    public var efficiencyCount: Int?
    public var id: String { fingerprint }

    public var averageEfficiency: Double? {
        guard let total = efficiencyTotal, let count = efficiencyCount, count > 0 else { return nil }
        return total / Double(count)
    }

    public var peakLoad: Double? {
        guard let ceilingWatts, ceilingWatts > 0 else { return nil }
        return peakInputWatts / ceilingWatts
    }
}

public struct ChargerLog: Codable, Equatable, Sendable {
    public private(set) var records: [ChargerRecord] = []

    public init(records: [ChargerRecord] = []) {
        self.records = records
    }

    /// Most recently used first.
    public var sorted: [ChargerRecord] {
        records.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Folds one reading in. Gaps longer than `maxGap` count as unplugged time, not use.
    public mutating func record(_ s: PowerSnapshot, verdict: String?, maxGap: TimeInterval = 30) {
        guard s.isExternalPower, let adapter = s.adapter else { return }
        let key = adapter.fingerprint
        guard let i = records.firstIndex(where: { $0.fingerprint == key }) else {
            records.append(ChargerRecord(
                fingerprint: key, title: adapter.title, ratedWatts: adapter.ratedWatts,
                ceilingWatts: adapter.ceilingWatts, profiles: adapter.profiles,
                firstSeen: s.date, lastSeen: s.date, secondsConnected: 0,
                peakInputWatts: s.inputWatts ?? 0, peakDemandWatts: s.demandWatts,
                lastVerdict: verdict,
                efficiencyTotal: ChargerEfficiency(snapshot: s)?.efficiency,
                efficiencyCount: ChargerEfficiency(snapshot: s) == nil ? nil : 1))
            return
        }
        var r = records[i]
        let gap = s.date.timeIntervalSince(r.lastSeen)
        if gap > 0 && gap <= maxGap { r.secondsConnected += gap }
        r.lastSeen = max(r.lastSeen, s.date)
        r.ceilingWatts = adapter.ceilingWatts ?? r.ceilingWatts
        r.peakInputWatts = max(r.peakInputWatts, s.inputWatts ?? 0)
        r.peakDemandWatts = max(r.peakDemandWatts, s.demandWatts)
        if let verdict { r.lastVerdict = verdict }
        if let e = ChargerEfficiency(snapshot: s) {
            r.efficiencyTotal = (r.efficiencyTotal ?? 0) + e.efficiency
            r.efficiencyCount = (r.efficiencyCount ?? 0) + 1
        }
        records[i] = r
    }

    public mutating func forget(_ fingerprint: String) {
        records.removeAll { $0.fingerprint == fingerprint }
    }
}
