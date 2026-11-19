import AppKit
import Darwin
import Observation
import WattsupCore

/// Ranks apps by energy impact using `top`, only while a view that shows it is open.
@MainActor @Observable
final class EnergyImpactMonitor {
    private(set) var apps: [AppImpact] = []
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var running = false

    func viewerAppeared() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func viewerDisappeared() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        guard !running else { return }
        running = true
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/top")
            // Two samples a second apart; the first is cumulative since boot and is discarded
            p.arguments = ["-l", "2", "-s", "1", "-stats", "pid,command,power", "-o", "power", "-n", "25"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            var output = ""
            do {
                try p.run()
                output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            } catch {
                log.error("Could not run top for energy impact: \(error.localizedDescription)")
            }
            let grouped = EnergyImpact.group(EnergyImpact.parse(top: output)) { pid in
                Self.path(of: pid).flatMap(EnergyImpact.appBundle(inPath:))
            }
            await MainActor.run {
                self.apps = Array(grouped.prefix(8))
                self.running = false
            }
        }
    }

    nonisolated static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }
}
