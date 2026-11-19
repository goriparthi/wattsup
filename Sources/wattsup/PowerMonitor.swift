import Foundation
import IOKit.ps
import Observation
import WattsupCore

/// Polls the battery controller, keeps history, and judges the charger. One per app.
@MainActor @Observable
final class PowerMonitor {
    enum Availability: Equatable {
        case loading, ready, noBattery, readFailed(String)
    }

    private(set) var availability: Availability = .loading
    private(set) var snapshot: PowerSnapshot?
    private(set) var history = PowerHistory()
    private(set) var assessment: ChargerAssessment?
    private(set) var chargers: ChargerLog

    @ObservationIgnored var onUpdate: (() -> Void)?
    let energy = EnergyModeController()
    @ObservationIgnored private let store = ChargerStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastFingerprint: String?
    @ObservationIgnored private var peripherals: [Peripheral] = []
    private static let peripheralScanEvery = 3
    /// Starts due, so the first reading already includes attached devices
    @ObservationIgnored private var ticksSincePeripheralScan = PowerMonitor.peripheralScanEvery

    init() {
        chargers = store.load()
    }

    func start(interval: TimeInterval = 2) {
        energy.start()
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observePowerSourceChanges()
    }

    func refresh() {
        switch SmartBattery.read() {
        case .noBattery:
            availability = .noBattery
            snapshot = nil
        case .failed(let message):
            availability = .readFailed(message)
            snapshot = nil
        case .properties(let props):
            guard var s = PowerSnapshot(registry: props) else {
                availability = .readFailed("The battery controller returned no charge reading.")
                log.error("AppleSmartBattery had no CurrentCapacity")
                break
            }
            s.energyMode = energy.effective(onCharger: s.isExternalPower)
            // USB enumeration is heavier than the battery read, so it runs every third tick
            if ticksSincePeripheralScan >= Self.peripheralScanEvery {
                peripherals = USBPeripherals.read()
                ticksSincePeripheralScan = 0
            }
            ticksSincePeripheralScan += 1
            s.peripherals = peripherals
            history.append(s)
            let a = ChargerAssessment(snapshot: s, history: history)
            let settled = a.verdict != .measuring && a.verdict != .unplugged
            chargers.record(s, verdict: settled ? a.headline : nil)
            snapshot = s
            assessment = a
            availability = .ready
            persistChargers(adapterChanged: s.adapter?.fingerprint != lastFingerprint)
            lastFingerprint = s.adapter?.fingerprint
        }
        onUpdate?()
    }

    func forgetCharger(_ fingerprint: String) {
        chargers.forget(fingerprint)
        persistChargers(adapterChanged: true)
    }

    func flush() {
        store.save(chargers)
    }

    private func persistChargers(adapterChanged: Bool) {
        guard adapterChanged || Date().timeIntervalSince(lastSave) > 60 else { return }
        store.save(chargers)
        lastSave = Date()
    }

    /// Plugging or unplugging refreshes at once instead of waiting for the next tick.
    private func observePowerSourceChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            log.error("Could not subscribe to power source changes; relying on polling")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
}

/// Persists the charger log under Application Support.
struct ChargerStore {
    let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wattsup", isDirectory: true)
            .appendingPathComponent("chargers.json")
    }()

    func load() -> ChargerLog {
        guard let data = try? Data(contentsOf: url) else { return ChargerLog() }
        do {
            return try decoder.decode(ChargerLog.self, from: data)
        } catch {
            // Keep the unreadable file for diagnosis rather than overwriting it silently
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            log.error("Charger log unreadable, moved aside: \(error.localizedDescription, privacy: .public)")
            return ChargerLog()
        }
    }

    func save(_ chargers: ChargerLog) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoder.encode(chargers).write(to: url, options: .atomic)
        } catch {
            log.error("Could not save charger log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
