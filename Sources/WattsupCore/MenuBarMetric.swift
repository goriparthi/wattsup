import Foundation

/// The meaning a reading's color carries; the app maps each tone to a real color.
public enum MetricTone: String, Sendable {
    case input, system, charging, draining, warning, neutral
}

/// A reading the user can pin to the menu bar. Power, volts and amps follow the live bus:
/// the charger input when plugged in, the battery pack when not.
public enum MenuBarMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case watts, volts, amps, systemWatts, batteryWatts, wallWatts, chargerLoad
    case percent, time, temperature, health, energyMode, peripherals

    /// Wall draw, Mac use, charger load and percent; the two charger readings drop out on battery.
    public static let defaults: [MenuBarMetric] = [.wallWatts, .systemWatts, .chargerLoad, .percent]
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .watts: return "Power in or out"
        case .volts: return "Voltage"
        case .amps: return "Current"
        case .systemWatts: return "Mac uses"
        case .batteryWatts: return "Battery power"
        case .wallWatts: return "From the wall"
        case .chargerLoad: return "Charger load"
        case .percent: return "Battery percent"
        case .time: return "Time to full or empty"
        case .temperature: return "Battery temperature"
        case .health: return "Battery health"
        case .energyMode: return "Energy mode"
        case .peripherals: return "Powering accessories"
        }
    }

    public var help: String {
        switch self {
        case .watts: return "Charger input when plugged in, Mac draw on battery"
        case .volts, .amps: return "Charger input when plugged in, battery pack on battery"
        case .systemWatts: return "What the Mac itself is using"
        case .batteryWatts: return "Plus while charging, minus while draining"
        case .wallWatts: return "Charger input plus its conversion loss"
        case .chargerLoad: return "Share of the charger's limit in use"
        case .energyMode: return "Shown only when Low or High Power is on"
        case .peripherals: return "Power the Mac allocated to USB devices, shown when any are plugged in"
        case .percent, .time, .temperature, .health: return ""
        }
    }

    /// Short reading for the status item, or nil when it has nothing to say right now.
    public func text(for s: PowerSnapshot) -> String? {
        switch self {
        case .watts: return String(format: "%.1fW", s.headlineWatts)
        case .volts: return String(format: "%.2fV", s.busVolts)
        case .amps: return String(format: "%.2fA", s.busAmps)
        case .systemWatts: return String(format: "%.1fW", s.systemWatts)
        case .batteryWatts:
            let w = abs(s.batteryWatts) < 0.05 ? 0 : s.batteryWatts
            return (w < 0 ? Units.minus : "+") + String(format: "%.1fW", abs(w))
        case .wallWatts: return s.wallWatts.map { String(format: "%.1fW", $0) }
        case .chargerLoad: return s.chargerLoad.map { String(format: "%.0f%%", $0 * 100) }
        case .percent: return "\(s.percent)%"
        case .time: return (s.minutesToFull ?? s.minutesToEmpty).map(Units.clock(minutes:))
        case .temperature: return s.temperatureC.map { String(format: "%.0f°C", $0) }
        case .health: return s.health.map { String(format: "%.0f%%", $0 * 100) }
        case .energyMode: return s.energyMode?.shortTitle
        case .peripherals:
            return s.peripherals.isEmpty ? nil : String(format: "USB %.0fW", s.peripherals.allocatedWatts)
        }
    }

    public func tone(for s: PowerSnapshot) -> MetricTone {
        switch self {
        case .watts, .volts, .amps: return s.isExternalPower ? .input : .draining
        case .systemWatts: return .system
        case .batteryWatts: return s.batteryWatts < -0.05 ? .draining : .charging
        case .wallWatts: return .input
        case .chargerLoad:
            guard let load = s.chargerLoad else { return .neutral }
            return load >= 0.9 ? .warning : load >= 0.75 ? .draining : .input
        case .percent:
            if s.state == .discharging && s.percent <= 20 { return .warning }
            return s.state == .charging ? .charging : .neutral
        case .time: return .neutral
        case .temperature: return (s.temperatureC ?? 0) >= 40 ? .warning : .neutral
        case .health: return (s.health ?? 1) < 0.8 ? .warning : .neutral
        case .energyMode: return s.energyMode == .high ? .warning : .charging
        case .peripherals: return .system
        }
    }

    public static func line(_ metrics: [MenuBarMetric], for s: PowerSnapshot) -> String {
        metrics.compactMap { $0.text(for: s) }.joined(separator: " ")
    }

    /// Splits readings into two rows for the stacked layout, top row taking the extra one.
    public static func rows(_ metrics: [MenuBarMetric]) -> [[MenuBarMetric]] {
        guard metrics.count > 1 else { return [metrics] }
        let top = (metrics.count + 1) / 2
        return [Array(metrics.prefix(top)), Array(metrics.dropFirst(top))]
    }

    /// Persisted as a comma separated string so it fits in UserDefaults. Unknown or repeated
    /// entries are dropped so an older or newer build never shows a reading twice.
    public static func decode(_ raw: String) -> [MenuBarMetric] {
        var seen = Set<MenuBarMetric>()
        return raw.split(separator: ",").compactMap { MenuBarMetric(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
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

    /// Electrical glyph for the menu bar: a filled bolt while charging, a plug while held or
    /// full on the charger, an outline bolt on battery.
    var powerSymbolName: String {
        switch state {
        case .charging: return "bolt.fill"
        case .full, .held: return "powerplug.fill"
        case .discharging: return "bolt"
        }
    }

    var symbolTone: MetricTone {
        switch state {
        case .charging: return .charging
        case .full, .held: return .input
        case .discharging: return percent <= 20 ? .warning : .draining
        }
    }
}
