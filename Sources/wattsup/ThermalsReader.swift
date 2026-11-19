import Foundation
import WattsupCore

/// Reads the SMC off the main thread. The sensor list is discovered once, then reused.
final class ThermalsReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.goriparthi.wattsup.smc", qos: .utility)
    private var smc: SMC?
    private var chipKeys: [String] = []
    private var started = false

    func read(_ completion: @escaping @Sendable (Thermals?) -> Void) {
        queue.async { [self] in
            if !started {
                started = true
                smc = SMC()
                chipKeys = smc?.allKeys().filter(Thermals.isChipSensor) ?? []
                log.info("Thermals: \(smc == nil ? "SMC unavailable" : "\(chipKeys.count) chip sensors")")
            }
            guard let smc else { return completion(nil) }
            var temps: [String: Double] = [:]
            for key in chipKeys { temps[key] = smc.read(key) }
            completion(Thermals.summarize(fans: smc.fans(), temperatures: temps))
        }
    }
}
