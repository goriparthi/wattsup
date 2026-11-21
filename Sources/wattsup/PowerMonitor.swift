import Foundation
import IOKit.ps
import Observation
import WattsupCore
import WidgetKit

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
    private(set) var quality: ChargerQuality?
    /// Stored minutes from the last 30 days, for the long charts and energy totals.
    private(set) var archive: [PowerSample] = []
    /// Daily battery health, for the wear trend.
    private(set) var healthPoints: [HealthPoint] = []
    /// Charging receipts, newest last, and the one just finished for an optional notification.
    private(set) var sessions: [ChargingSession] = []
    private(set) var latestReceipt: ChargingSession?

    @ObservationIgnored var onUpdate: (() -> Void)?
    let energy = EnergyModeController()
    let impact = EnergyImpactMonitor()
    let accessories = AccessoryBatteryReader()
    @ObservationIgnored private let store = ChargerStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastFingerprint: String?
    @ObservationIgnored private var peripherals: [Peripheral] = []
    @ObservationIgnored private let thermalsReader = ThermalsReader()
    @ObservationIgnored private var thermals: Thermals?
    @ObservationIgnored private var lastDisconnect: (fingerprint: String, at: Date)?
    @ObservationIgnored private var ticksSinceQuality = 0
    @ObservationIgnored private let historyStore = HistoryStore()
    @ObservationIgnored private var minutes = MinuteAggregator()
    @ObservationIgnored private let healthStore = HealthStore()
    @ObservationIgnored private let sessionStore = SessionStore()
    @ObservationIgnored private var tracker = SessionTracker()
    @ObservationIgnored private var lastWidget: WidgetSnapshot?
    private static let peripheralScanEvery = 3
    /// Starts due, so the first reading already includes attached devices
    @ObservationIgnored private var ticksSincePeripheralScan = PowerMonitor.peripheralScanEvery

    init() {
        chargers = store.load()
        chargers.pruneTransient()
        healthPoints = healthStore.load()
        sessions = sessionStore.load()
        archive = historyStore.load(days: HistoryStore.keepDays)
        historyStore.prune()
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
                accessories.refreshIfDue()
                thermalsReader.read { [weak self] t in
                    DispatchQueue.main.async { self?.thermals = t }
                }
                ticksSincePeripheralScan = 0
            }
            ticksSincePeripheralScan += 1
            s.peripherals = peripherals
            s.thermals = thermals
            s.recentWatts = history.recent(60, from: s.date).map { $0.isExternalPower ? $0.inputWatts : $0.systemWatts } + [s.headlineWatts]
            history.append(s)
            if let minute = minutes.add(PowerSample(s)) {
                historyStore.append(minute)
                archive.append(minute)
                let cutoff = s.date.addingTimeInterval(-Double(HistoryStore.keepDays) * 86400)
                if let first = archive.firstIndex(where: { $0.date >= cutoff }), first > 0 { archive.removeFirst(first) }
            }
            let a = ChargerAssessment(snapshot: s, history: history, known: chargers.records)
            // Nothing is logged while the charger is still negotiating its real power profile
            if a.verdict != .negotiating { chargers.record(s, verdict: a.verdict.isSettled ? a.headline : nil) }
            recordHealth(s)
            let limited = a.verdict == .bottleneck || a.verdict == .notKeepingUp
            if let done = tracker.update(s, limited: limited) { finishSession(done) }
            trackDropouts(from: snapshot, to: s)
            updateQuality(s)
            publishToWidget(s, verdict: a)
            logTransitions(from: snapshot, to: s, verdict: a)
            snapshot = s
            assessment = a
            availability = .ready
            persistChargers(adapterChanged: s.adapter?.fingerprint != lastFingerprint)
            lastFingerprint = s.adapter?.fingerprint
        }
        onUpdate?()
    }

    /// Writes the widget's reading into its container and asks WidgetKit to redraw, only when
    /// something a glance would notice changed, since widget reloads are rationed.
    private func publishToWidget(_ s: PowerSnapshot, verdict a: ChargerAssessment) {
        let w = WidgetSnapshot(s, verdict: a.verdict.isSettled ? a.headline : nil)
        guard w.differsMeaningfully(from: lastWidget), let data = w.encoded() else { return }
        lastWidget = w
        let url = WidgetSnapshot.containerURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: "WattsupWidget")
        } catch {
            log.error("Could not write the widget reading: \(error.localizedDescription)")
        }
    }

    private func recordHealth(_ s: PowerSnapshot) {
        guard let health = s.health, let cycles = s.cycleCount else { return }
        let point = HealthPoint(date: s.date, health: health, cycles: cycles, nominalCapacity: s.nominalCapacity)
        guard HealthTrend.shouldRecord(point, after: healthPoints.last) else { return }
        healthStore.append(point)
        healthPoints.append(point)
    }

    /// A replug of the same charger within 10 s counts as a drop-out against it.
    private func trackDropouts(from old: PowerSnapshot?, to s: PowerSnapshot) {
        if let fp = old?.adapter?.fingerprint, old?.isExternalPower == true, !s.isExternalPower {
            lastDisconnect = (fp, s.date)
        }
        if let d = lastDisconnect, let fp = s.adapter?.fingerprint, s.isExternalPower {
            if fp == d.fingerprint && s.date.timeIntervalSince(d.at) <= 10 {
                chargers.noteDropout(fp)
                log.warning("Charger dropped out and reconnected within \(Int(s.date.timeIntervalSince(d.at))) s")
            }
            lastDisconnect = nil
        }
    }

    /// The report card scans the whole history, so it runs every fifth tick.
    private func updateQuality(_ s: PowerSnapshot) {
        guard let adapter = s.adapter, s.isExternalPower else { quality = nil; return }
        ticksSinceQuality += 1
        guard quality == nil || ticksSinceQuality >= 5 else { return }
        ticksSinceQuality = 0
        let q = ChargerQuality(adapter: adapter, samples: history.samples,
                               dropouts: chargers.dropouts(adapter.fingerprint),
                               thermallyLimitedSeconds: s.thermallyLimitedSeconds)
        if q.overall != quality?.overall, let grade = q.overall {
            log.info("Charger report card: \(grade.title)" + (q.resistanceOhms.map { String(format: ", cable %.2f ohm", $0) } ?? ""))
        }
        quality = q
        chargers.store(q, for: adapter.fingerprint)
    }

    /// Logs only what changed, so the file reads as a timeline of plug events and verdicts.
    private func logTransitions(from old: PowerSnapshot?, to s: PowerSnapshot, verdict: ChargerAssessment) {
        if old?.isExternalPower != s.isExternalPower {
            log.info(s.isExternalPower ? "Charger connected" : "Charger disconnected, on battery at \(s.percent)%")
        }
        if let a = s.adapter, old?.adapter?.fingerprint != a.fingerprint {
            let profile = a.activeProfile.map { Units.profile($0) } ?? "no active profile"
            log.info("Charger: \(a.title), negotiated \(Units.volts(a.negotiatedVolts, digits: 1)) at \(Units.amps(a.negotiatedAmps)), active \(profile), \(a.profiles.count) profiles")
            if ChargerAssessment.looksCableCapped(a) { log.info("Charger menu stops at 20 V 3 A; cable likely limits it to 60 W") }
        }
        if old?.state != s.state { log.info("State: \(s.state.title) at \(s.percent)%") }
        if verdict.verdict != assessment?.verdict, verdict.verdict.isSettled || verdict.verdict == .negotiating {
            log.info("Charger check: \(verdict.headline). \(verdict.detail)")
        }
        if old?.peripherals.map(\.name) != s.peripherals.map(\.name) {
            log.info(s.peripherals.isEmpty ? "No powered accessories"
                     : "Powering: " + s.peripherals.map { "\($0.name) up to \(Units.watts($0.allocatedWatts))" }.joined(separator: ", "))
        }
    }

    /// Names stay in the local charger file only and are never written to the log.
    func renameCharger(_ fingerprint: String, _ name: String) {
        chargers.rename(fingerprint, to: name)
        persistChargers(adapterChanged: true)
    }

    func mergeCharger(_ source: String, _ target: String) {
        chargers.merge(source, into: target)
        persistChargers(adapterChanged: true)
    }

    func separateCharger(_ fingerprint: String) {
        chargers.separate(fingerprint)
        persistChargers(adapterChanged: true)
    }

    func forgetBrick(_ brick: String) {
        chargers.forgetBrick(brick)
        persistChargers(adapterChanged: true)
    }

    func forgetCharger(_ fingerprint: String) {
        chargers.forget(fingerprint)
        persistChargers(adapterChanged: true)
    }

    private func finishSession(_ session: ChargingSession) {
        sessionStore.append(session)
        sessions.append(session)
        latestReceipt = session
        log.info("Charging session ended: \(session.summary)")
    }

    func flush() {
        if let open = tracker.current { sessionStore.append(open) }
        if let partial = minutes.pending() { historyStore.append(partial) }
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
            log.error("Charger log unreadable, moved aside: \(error.localizedDescription)")
            return ChargerLog()
        }
    }

    func save(_ chargers: ChargerLog) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoder.encode(chargers).write(to: url, options: .atomic)
        } catch {
            log.error("Could not save charger log: \(error.localizedDescription)")
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
