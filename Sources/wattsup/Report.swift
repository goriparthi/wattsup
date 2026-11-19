import Foundation
import WattsupCore

/// Plain text reading for `wattsup --snapshot`, used by scripts and the bundle check.
enum Report {
    static func printSnapshot() -> Int32 {
        switch SmartBattery.read() {
        case .noBattery:
            print("No battery found")
            return 3
        case .failed(let message):
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        case .properties(let props):
            guard let s = PowerSnapshot(registry: props) else {
                FileHandle.standardError.write(Data("battery reading had no charge level\n".utf8))
                return 1
            }
            print(lines(s).joined(separator: "\n"))
            return 0
        }
    }

    static func lines(_ s: PowerSnapshot) -> [String] {
        var out = ["Battery    \(s.percent)%  \(s.statusLine)"]
        if let a = s.adapter {
            out.append("Charger    \(a.title), \(Units.volts(a.negotiatedVolts, digits: 1)) at \(Units.amps(a.negotiatedAmps))")
            out.append("Input      \(Units.watts(s.inputWatts))  \(Units.volts(s.inputVolts))  \(Units.amps(s.inputAmps))  load \(Units.percent(s.chargerLoad))")
        }
        out.append("Mac uses   \(Units.watts(s.systemWatts))")
        out.append("Battery    \(Units.watts(s.batteryWatts, signed: true))  \(Units.volts(s.batteryVolts))  \(Units.amps(s.batteryAmps))")
        if let w = s.requestedBatteryWatts { out.append("Requested  \(Units.watts(w)) by the battery, demand \(Units.watts(s.demandWatts))") }
        out.append("Health     \(Units.percent(s.health, digits: 1)), \(s.cycleCount ?? 0) cycles, \(Units.celsius(s.temperatureC))")
        if !s.cellVolts.isEmpty {
            out.append("Cells      " + s.cellVolts.map { Units.volts($0, digits: 3) }.joined(separator: "  "))
        }
        return out
    }
}
