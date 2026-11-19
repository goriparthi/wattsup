import AppKit
import Foundation
import os
import WattsupCore

/// App logging: every entry goes to ~/Library/Logs/Wattsup/wattsup.log and the unified log.
struct AppLog {
    static let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Wattsup", isDirectory: true)
    static let file = LogFile(directory: directory)
    private let system = Logger(subsystem: "com.goriparthi.wattsup", category: "app")

    func info(_ message: String) {
        system.info("\(message, privacy: .public)")
        Self.file.write(.info, message)
    }

    func warning(_ message: String) {
        system.warning("\(message, privacy: .public)")
        Self.file.write(.warning, message)
    }

    func error(_ message: String) {
        system.error("\(message, privacy: .public)")
        Self.file.write(.error, message)
    }
}

let log = AppLog()

/// Crash capture: a marker that only a clean quit removes, plus the macOS crash report it points to.
enum Diagnostics {
    static let crashDirectory = AppLog.directory.appendingPathComponent("Crashes", isDirectory: true)
    private static let marker = AppLog.directory.appendingPathComponent("running")
    private static let systemReports = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)

    static func launched(version: String) {
        let previous = (try? FileManager.default.attributesOfItem(atPath: marker.path)[.modificationDate]) as? Date
        log.info("Wattsup \(version) launched on \(hardwareModel()), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if let previous {
            log.error("Previous run started \(previous) and did not quit cleanly")
            collectCrashReports(since: previous)
        }
        FileManager.default.createFile(atPath: marker.path, contents: Data(version.utf8))
        // A plain kill (installers, logout scripts) is a normal stop, so route it through
        // the clean quit path instead of leaving the marker behind
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            log.info("Received SIGTERM")
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSource = source
        NSSetUncaughtExceptionHandler { exception in
            AppLog.file.writeNow(.error, "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.prefix(20).joined(separator: "\n"))
        }
    }

    private static var terminationSource: DispatchSourceSignal?

    static func quitCleanly() {
        log.info("Quit cleanly")
        try? FileManager.default.removeItem(at: marker)
        AppLog.file.flush()
    }

    /// Copies macOS's crash reports for this app into the log folder so they travel together.
    private static func collectCrashReports(since start: Date) {
        let fm = FileManager.default
        let reports = (try? fm.contentsOfDirectory(at: systemReports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let ours = reports.filter {
            $0.lastPathComponent.lowercased().hasPrefix("wattsup")
                && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= start
        }
        guard !ours.isEmpty else {
            log.warning("No macOS crash report found for that run; it may have been force quit or killed")
            return
        }
        try? fm.createDirectory(at: crashDirectory, withIntermediateDirectories: true)
        for report in ours {
            let destination = crashDirectory.appendingPathComponent(report.lastPathComponent)
            try? fm.removeItem(at: destination)
            do {
                try fm.copyItem(at: report, to: destination)
                log.error("Crash report saved: \(destination.path)")
            } catch {
                log.error("Could not copy crash report \(report.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    static func revealInFinder() {
        AppLog.file.flush()
        NSWorkspace.shared.activateFileViewerSelecting([AppLog.file.url])
    }

    /// `wattsup --diagnostics`: where the logs live, the recent log, and saved crash reports.
    static func printReport(lines: Int = 60) {
        print("Log folder: \(AppLog.directory.path)")
        let crashes = (try? FileManager.default.contentsOfDirectory(atPath: crashDirectory.path))?.sorted() ?? []
        print("Saved crash reports: \(crashes.isEmpty ? "none" : "")")
        crashes.forEach { print("  \(crashDirectory.appendingPathComponent($0).path)") }
        print("\nLast \(lines) log lines:")
        AppLog.file.tail(lines).forEach { print($0) }
    }
}
