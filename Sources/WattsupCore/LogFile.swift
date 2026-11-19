import Foundation

/// Append-only log file with size based rotation: wattsup.log, wattsup.log.1, and so on.
/// Writes are serialized on a private queue; `flush` blocks until they reach disk.
public final class LogFile: @unchecked Sendable {
    public enum Level: String, Sendable {
        case debug = "DEBUG", info = "INFO", warning = "WARN", error = "ERROR"
    }

    public let url: URL
    private let maxBytes: Int
    private let keep: Int
    private let queue = DispatchQueue(label: "com.goriparthi.wattsup.log")
    private var handle: FileHandle?

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public init(directory: URL, name: String = "wattsup.log", maxBytes: Int = 1_000_000, keep: Int = 3) {
        url = directory.appendingPathComponent(name)
        self.maxBytes = maxBytes
        self.keep = max(1, keep)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// One line per entry, UTC timestamped, with newlines escaped so an entry never splits.
    public static func line(_ level: Level, _ message: String, date: Date) -> String {
        let flat = message.replacingOccurrences(of: "\n", with: "\\n")
        return "\(formatter.string(from: date)) \(level.rawValue) \(flat)\n"
    }

    public func write(_ level: Level, _ message: String, date: Date = Date()) {
        let data = Data(Self.line(level, message, date: date).utf8)
        queue.async { self.append(data) }
    }

    /// Writes synchronously, for paths that may not survive to run the queue.
    public func writeNow(_ level: Level, _ message: String, date: Date = Date()) {
        let data = Data(Self.line(level, message, date: date).utf8)
        queue.sync { self.append(data) }
    }

    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    /// The last `count` lines of the current file.
    public func tail(_ count: Int) -> [String] {
        flush()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(count).map(String.init))
    }

    private func append(_ data: Data) {
        rotateIfNeeded(adding: data.count)
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        try? handle?.write(contentsOf: data)
    }

    private func rotateIfNeeded(adding bytes: Int) {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 0, size + bytes > maxBytes else { return }
        try? handle?.close()
        handle = nil
        let rotated = { (n: Int) in URL(fileURLWithPath: self.url.path + ".\(n)") }
        try? fm.removeItem(at: rotated(keep))
        for n in stride(from: keep - 1, through: 1, by: -1) where fm.fileExists(atPath: rotated(n).path) {
            try? fm.moveItem(at: rotated(n), to: rotated(n + 1))
        }
        try? fm.moveItem(at: url, to: rotated(1))
    }
}
