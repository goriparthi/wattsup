import AppKit
import Foundation
import Observation
import WattsupCore

/// Reads Energy Mode from pmset and changes it through the standard admin prompt,
/// since only root may write power settings.
@MainActor @Observable
final class EnergyModeController {
    private(set) var modes: EnergyModes?
    private(set) var busy = false
    private(set) var error: String?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var timer: Timer?

    func start() {
        refresh()
        // Fires when Low Power changes anywhere, including System Settings
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func effective(onCharger: Bool) -> EnergyMode? {
        modes?.mode(for: onCharger ? .charger : .battery)
    }

    func refresh() {
        Task {
            let result = await Self.run("/usr/bin/pmset", ["-g", "custom"])
            if result.status == 0 {
                modes = EnergyModes.parse(pmsetCustom: result.output)
            } else {
                log.error("pmset -g custom failed with \(result.status)")
            }
        }
    }

    func set(_ mode: EnergyMode, for source: PowerSource) {
        guard let modes, !busy, modes.mode(for: source) != mode else { return }
        // Arguments come only from the enum, never from text, so nothing needs escaping
        let command = (["/usr/bin/pmset"] + modes.pmsetArguments(mode, for: source)).joined(separator: " ")
        let script = "do shell script \"\(command)\" with administrator privileges"
        busy = true
        error = nil
        Task {
            let result = await Self.run("/usr/bin/osascript", ["-e", script])
            busy = false
            if result.status != 0 && !result.output.contains("-128") {
                // -128 is the user cancelling the prompt, which is not an error
                error = "Could not change Energy Mode."
                log.error("Energy Mode change failed: \(result.output, privacy: .public)")
            }
            refresh()
        }
    }

    private static func run(_ path: String, _ args: [String]) async -> (status: Int32, output: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return (127, error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}

enum SystemSettings {
    static func openMenuBar() {
        open("x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
    }

    static func openBattery() {
        open("x-apple.systempreferences:com.apple.Battery-Settings.extension")
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
