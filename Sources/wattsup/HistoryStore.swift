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
