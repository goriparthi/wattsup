import Foundation
import WattsupCore

/// Minute history on disk: Application Support/Wattsup/history/<UTC day>.jsonl, 30 days kept.
struct HistoryStore {
    static let keepDays = 30
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wattsup/history", isDirectory: true)

    func append(_ minute: PowerSample) {
        guard let data = HistoryArchive.encode(minute) else { return }
        let url = directory.appendingPathComponent(HistoryArchive.fileName(for: minute.date))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            log.error("Could not write history: \(error.localizedDescription)")
        }
    }

    /// Minutes from the last `days` days, oldest first.
    func load(days: Int, now: Date = Date()) -> [PowerSample] {
        let names = (0..<days).reversed().map { HistoryArchive.fileName(for: now.addingTimeInterval(-Double($0) * 86400)) }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return names.flatMap { name -> [PowerSample] in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return [] }
            return HistoryArchive.decode(data)
        }
        .filter { $0.date >= cutoff }
        .sorted { $0.date < $1.date }
    }

    func prune(now: Date = Date()) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in HistoryArchive.expired(names, now: now, days: Self.keepDays) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

/// Daily battery health records: Application Support/Wattsup/health.jsonl, kept indefinitely
/// (one small line a day) because wear is only visible over months.
struct HealthStore {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wattsup/health.jsonl")

    func load() -> [HealthPoint] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return data.split(separator: 0x0A).compactMap { try? d.decode(HealthPoint.self, from: Data($0)) }
    }

    func append(_ point: HealthPoint) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        guard var line = try? e.encode(point) else { return }
        line.append(0x0A)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            log.error("Could not write battery health: \(error.localizedDescription)")
        }
    }
}

/// Charging receipts: Application Support/Wattsup/sessions.jsonl, one line per plug in.
struct SessionStore {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wattsup/sessions.jsonl")

    func load() -> [ChargingSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return data.split(separator: 0x0A).compactMap { try? d.decode(ChargingSession.self, from: Data($0)) }
    }

    func append(_ session: ChargingSession) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        guard var line = try? e.encode(session) else { return }
        line.append(0x0A)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            log.error("Could not write a charging receipt: \(error.localizedDescription)")
        }
    }
}
