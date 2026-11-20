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
    /// Report card results; optional so older logs still decode.
    public var dropouts: Int?
    public var qualityGrade: Int?
    public var resistanceOhms: Double?
    public var sagFraction: Double?

    public var quality: ChargerQuality.Grade? { qualityGrade.flatMap(ChargerQuality.Grade.init(rawValue:)) }

    /// A name the user gave this charger; optional so older logs still decode.
    public var nickname: String?
    /// Entries the user marked as the same physical charger share this id: the root entry's
    /// fingerprint. Nil means the entry stands alone.
    public var brickID: String?
    public var brick: String { brickID ?? fingerprint }
    public var displayName: String { (nickname?.isEmpty == false ? nickname : nil) ?? title }
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
        // A charger seen before serials were read: adopt its old entry under the serial identity
        if adapter.serial != nil, !records.contains(where: { $0.fingerprint == key }),
           let old = records.firstIndex(where: { $0.fingerprint == adapter.legacyFingerprint }) {
            let previous = records[old].fingerprint
            records[old].fingerprint = key
            for j in records.indices where records[j].brickID == previous { records[j].brickID = key }
        }
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

    public mutating func noteDropout(_ fingerprint: String) {
        guard let i = records.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        records[i].dropouts = (records[i].dropouts ?? 0) + 1
    }

    public func dropouts(_ fingerprint: String) -> Int {
        records.first { $0.fingerprint == fingerprint }?.dropouts ?? 0
    }

    public mutating func store(_ q: ChargerQuality, for fingerprint: String) {
        guard let i = records.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        records[i].qualityGrade = q.overall?.rawValue
        if let r = q.resistanceOhms { records[i].resistanceOhms = r }
        if let s = q.sagFraction { records[i].sagFraction = s }
    }

    /// Drops entries that were only a moment of plug in negotiation (a brief 5 V profile before
    /// the real one), never judged and seen for under 20 seconds, once they are an hour old.
    public mutating func pruneTransient(now: Date = Date()) {
        records.removeAll {
            $0.lastVerdict == nil && $0.secondsConnected < 20 && now.timeIntervalSince($0.lastSeen) > 3600
        }
    }

    /// Names a charger; an empty name clears it back to the detected title.
    public mutating func rename(_ fingerprint: String, to name: String) {
        guard let i = records.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        records[i].nickname = trimmed.isEmpty ? nil : String(trimmed.prefix(40))
    }

    public func record(for fingerprint: String?) -> ChargerRecord? {
        records.first { $0.fingerprint == fingerprint }
    }

    /// The name to show for a connected charger, following a merge to its brick's name.
    public func name(for fingerprint: String?) -> String? {
        guard let r = record(for: fingerprint) else { return nil }
        return records.first { $0.fingerprint == r.brick }?.nickname ?? r.nickname
    }

    /// Marks `source` as the same physical charger as `target`. Everything already grouped with
    /// the source moves too; a name on the source is kept if the target has none.
    public mutating func merge(_ source: String, into target: String) {
        guard source != target, let s = record(for: source), let t = record(for: target) else { return }
        let from = s.brick, to = t.brick
        guard from != to else { return }
        let carriedName = records.first { $0.fingerprint == from }?.nickname
        for i in records.indices where records[i].brick == from { records[i].brickID = to }
        if let root = records.firstIndex(where: { $0.fingerprint == to }) {
            if records[root].nickname == nil { records[root].nickname = carriedName }
            records[root].brickID = nil
        }
        for i in records.indices where records[i].fingerprint == from { records[i].nickname = nil }
    }

    /// Takes one entry back out of its brick. If it was the root, the next member becomes the root.
    public mutating func separate(_ fingerprint: String) {
        guard let i = records.firstIndex(where: { $0.fingerprint == fingerprint }) else { return }
        let brick = records[i].brick
        if brick == fingerprint {
            let others = records.indices.filter { records[$0].brickID == fingerprint }
            guard let heir = others.first else { return }
            let newRoot = records[heir].fingerprint
            records[heir].brickID = nil
            records[heir].nickname = records[i].nickname
            for j in others.dropFirst() { records[j].brickID = newRoot }
        } else {
            records[i].brickID = nil
        }
    }

    /// Forgets a whole brick: every entry grouped under it.
    public mutating func forgetBrick(_ brick: String) {
        records.removeAll { $0.brick == brick }
    }

    public mutating func forget(_ fingerprint: String) {
        records.removeAll { $0.fingerprint == fingerprint }
    }
}
