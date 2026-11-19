import Foundation

/// macOS Energy Mode. High Power exists only on Macs whose pmset reports `powermode`.
public enum EnergyMode: Int, CaseIterable, Identifiable, Sendable {
    case automatic = 0, low = 1, high = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .low: return "Low Power"
        case .high: return "High Power"
        }
    }

    /// Menu bar text; nil for Automatic so the reading only appears when it matters.
    public var shortTitle: String? {
        switch self {
        case .automatic: return nil
        case .low: return "Low"
        case .high: return "High"
        }
    }
}

public enum PowerSource: String, CaseIterable, Sendable {
    case battery, charger

    /// The pmset flag that scopes a setting to this source.
    public var pmsetFlag: String { self == .battery ? "-b" : "-c" }
    public var title: String { self == .battery ? "On battery" : "On charger" }
}

/// Energy Mode settings for both power sources, parsed from `pmset -g custom`.
public struct EnergyModes: Equatable, Sendable {
    public var battery: EnergyMode?
    public var charger: EnergyMode?
    /// True when pmset uses `powermode`, which is also the only way High Power is offered.
    public var usesPowerModeKey: Bool

    public var available: [EnergyMode] {
        usesPowerModeKey ? EnergyMode.allCases : [.automatic, .low]
    }

    public func mode(for source: PowerSource) -> EnergyMode? {
        source == .battery ? battery : charger
    }

    /// The pmset key and value that set `mode`, so callers never build commands from text.
    public func pmsetArguments(_ mode: EnergyMode, for source: PowerSource) -> [String] {
        let key = usesPowerModeKey ? "powermode" : "lowpowermode"
        let value = usesPowerModeKey ? mode.rawValue : (mode == .low ? 1 : 0)
        return [source.pmsetFlag, key, String(value)]
    }

    public static func parse(pmsetCustom output: String) -> EnergyModes {
        var section: PowerSource?
        var values: [PowerSource: [String: Int]] = [:]
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Battery Power") { section = .battery; continue }
            if line.hasPrefix("AC Power") { section = .charger; continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let section, parts.count >= 2, let value = Int(parts[1]) else { continue }
            values[section, default: [:]][String(parts[0])] = value
        }
        let usesPowerMode = values.values.contains { $0["powermode"] != nil }
        func mode(_ source: PowerSource) -> EnergyMode? {
            guard let v = values[source] else { return nil }
            if let p = v["powermode"] { return EnergyMode(rawValue: p) }
            return v["lowpowermode"].map { $0 == 1 ? .low : .automatic }
        }
        return EnergyModes(battery: mode(.battery), charger: mode(.charger), usesPowerModeKey: usesPowerMode)
    }
}
