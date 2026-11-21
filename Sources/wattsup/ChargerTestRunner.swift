import Foundation
import Observation
import WattsupCore

/// The one click charger and cable test: a short burst of CPU load swings the input current so
/// the report card can grade the cable on the spot. Runs only on request, only on a charger.
@MainActor @Observable
final class ChargerTestRunner {
    enum Phase: String { case idle = "Measuring at rest", load = "Loading the Mac", recover = "Letting it settle" }
    enum State {
        case ready
        case running(phase: Phase, progress: Double)
        case done(quality: ChargerQuality, at: Date, currentSwing: Double)
        case failed(String)
    }

    private(set) var state: State = .ready
    @ObservationIgnored private var samples: [PowerSample] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = Date()
    @ObservationIgnored private var adapter: AdapterInfo?
    @ObservationIgnored private let load = CPULoad()
    @ObservationIgnored var hottestCore: () -> Double? = { nil }
    @ObservationIgnored var finished: (ChargerQuality, AdapterInfo) -> Void = { _, _ in }

    static let idleSeconds = 5.0, loadSeconds = 10.0, recoverSeconds = 5.0
    static var total: Double { idleSeconds + loadSeconds + recoverSeconds }

    var isRunning: Bool { if case .running = state { return true } else { return false } }

    func start(on snapshot: PowerSnapshot?) {
        guard !isRunning else { return }
        guard let s = snapshot, s.isExternalPower, let adapter = s.adapter else {
            state = .failed("Plug in a charger to test it.")
            return
        }
        self.adapter = adapter
        samples = []
        started = Date()
        state = .running(phase: .idle, progress: 0)
        log.info("Charger test started")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel(_ reason: String = "Cancelled.") {
        stop()
        state = .failed(reason)
        log.info("Charger test stopped: \(reason)")
    }

    private func stop() {
        load.stop()
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(started)
        guard case .properties(let props) = SmartBattery.read(), let s = PowerSnapshot(registry: props) else { return }
        guard s.isExternalPower, s.adapter?.fingerprint == adapter?.fingerprint else {
            cancel("The charger was unplugged or changed, so the test stopped.")
            return
        }
        if let hot = hottestCore(), hot >= 95 {
            cancel(String(format: "Stopped early: the chip reached %.0f °C.", hot))
            return
        }
        samples.append(PowerSample(s))

        let phase: Phase = elapsed < Self.idleSeconds ? .idle
            : elapsed < Self.idleSeconds + Self.loadSeconds ? .load : .recover
        if phase == .load { load.start() } else { load.stop() }
        state = .running(phase: phase, progress: min(1, elapsed / Self.total))
        if elapsed >= Self.total { finish() }
    }

    private func finish() {
        stop()
        guard let adapter else { return }
        let quality = ChargerQuality(adapter: adapter, samples: samples, dropouts: 0, thermallyLimitedSeconds: 0)
        let amps = samples.map(\.busAmps)
        let swing = (amps.max() ?? 0) - (amps.min() ?? 0)
        state = .done(quality: quality, at: Date(), currentSwing: swing)
        finished(quality, adapter)
        log.info("Charger test finished: \(quality.overall?.title ?? "ungraded"), current swing \(String(format: "%.2f", swing)) A"
                 + (quality.resistanceOhms.map { String(format: ", cable %.2f ohm", $0) } ?? ""))
    }
}

/// Busy work on every core while running; checked often so stop takes effect within milliseconds.
final class CPULoad: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var threads = 0

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        running = true
        let count = ProcessInfo.processInfo.activeProcessorCount
        threads = count
        for _ in 0..<count {
            Thread.detachNewThread { [weak self] in
                var x = 0.0
                while self?.isRunning == true {
                    for i in 0..<50_000 { x += (Double(i) + x).squareRoot() }
                    if x == .infinity { x = 0 }
                }
            }
        }
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }
}
