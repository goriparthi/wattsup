import Foundation

/// A reading the user can pin to the menu bar. Power, volts and amps follow the live bus:
/// the charger input when plugged in, the battery pack when not.
public enum MenuBarMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case watts, volts, amps, batteryWatts, percent, time, temperature, chargerLoad

    public static let defaults: [MenuBarMetric] = [.watts, .volts, .amps]
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .watts: return "Power (W)"
        case .volts: return "Voltage (V)"
        case .amps: return "Current (A)"
        case .batteryWatts: return "Battery power"
        case .percent: return "Battery %"
        case .time: return "Time to full or empty"
        case .temperature: return "Battery temperature"
        case .chargerLoad: return "Charger load %"
        }
    }

    /// Short reading for the status item, or nil when it has nothing to say right now.
    public func text(for s: PowerSnapshot) -> String? {
        switch self {
        case .watts: return String(format: "%.1fW", s.headlineWatts)
        case .volts: return String(format: "%.2fV", s.busVolts)
        case .amps: return String(format: "%.2fA", s.busAmps)
        case .batteryWatts: return String(format: "%+.1fW", s.batteryWatts)
        case .percent: return "\(s.percent)%"
        case .time:
            return (s.minutesToFull ?? s.minutesToEmpty).map(Units.clock(minutes:))
        case .temperature: return s.temperatureC.map { String(format: "%.0f°", $0) }
        case .chargerLoad: return s.chargerLoad.map { String(format: "%.0f%%", $0 * 100) }
        }
    }

    public static func line(_ metrics: [MenuBarMetric], for s: PowerSnapshot) -> String {
        metrics.compactMap { $0.text(for: s) }.joined(separator: " ")
    }

    /// Persisted as a comma separated string so it fits in UserDefaults and @AppStorage.
    public static func decode(_ raw: String) -> [MenuBarMetric] {
        raw.split(separator: ",").compactMap { MenuBarMetric(rawValue: String($0)) }
    }

    public static func encode(_ metrics: [MenuBarMetric]) -> String {
        metrics.map(\.rawValue).joined(separator: ",")
    }
}

public extension PowerSnapshot {
    /// SF Symbol name for the status item and the flow diagram.
    var symbolName: String {
        switch state {
        case .charging: return "battery.100percent.bolt"
        case .full, .held: return "powerplug.fill"
        case .discharging:
            switch percent {
            case 88...: return "battery.100percent"
            case 63..<88: return "battery.75percent"
            case 38..<63: return "battery.50percent"
            case 13..<38: return "battery.25percent"
            default: return "battery.0percent"
            }
        }
    }
}
