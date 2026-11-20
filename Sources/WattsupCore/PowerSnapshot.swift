import Foundation

/// One fixed voltage profile a USB-C Power Delivery charger offers.
public struct PDProfile: Identifiable, Equatable, Codable, Sendable {
    public var index: Int
    public var volts: Double
    public var amps: Double
    public var watts: Double { volts * amps }
    public var id: Int { index }

    public init(index: Int, volts: Double, amps: Double) {
        self.index = index
        self.volts = volts
        self.amps = amps
    }
}

public struct AdapterInfo: Equatable, Sendable {
    public var name: String?
    public var manufacturer: String?
    public var ratedWatts: Int?
    public var negotiatedVolts: Double?
    public var negotiatedAmps: Double?
    public var isWireless: Bool
    public var profiles: [PDProfile]
    public var activeProfileIndex: Int?
    public var familyCode: Int?
    /// Reported by Apple's own chargers; third party bricks leave it out.
    public var serial: String?

    public var activeProfile: PDProfile? {
        profiles.first { $0.index == activeProfileIndex }
    }

    public var bestProfile: PDProfile? {
        profiles.max { $0.watts < $1.watts }
    }

    /// The most the charger can deliver on the profile in use, which is the real ceiling.
    public var ceilingWatts: Double? {
        if let v = negotiatedVolts, let a = negotiatedAmps, v > 0, a > 0 { return v * a }
        if let p = activeProfile { return p.watts }
        return ratedWatts.map(Double.init)
    }

    public var title: String {
        if let name { return name }
        if let ratedWatts { return "\(ratedWatts) W \(isWireless ? "wireless" : "USB-C") charger" }
        return "Power adapter"
    }

    /// Identity for remembering a charger across plug ins. A charger that reports a serial number
    /// is that serial; the rest are identified by what they negotiate, so identical units merge.
    public var fingerprint: String {
        if let serial, !serial.isEmpty { return "serial|" + serial }
        return legacyFingerprint
    }

    /// The identity used before serials were read, kept so older entries can be matched up.
    public var legacyFingerprint: String {
        let pdos = profiles.map { "\(Int($0.volts * 1000))x\(Int($0.amps * 1000))" }
        return [name ?? "", manufacturer ?? "", ratedWatts.map(String.init) ?? "",
                familyCode.map(String.init) ?? "", pdos.joined(separator: ",")]
            .joined(separator: "|")
    }
}

public enum ChargeState: String, Equatable, Sendable {
    case charging, full, held, discharging

    public var title: String {
        switch self {
        case .charging: return "Charging"
        case .full: return "Fully charged"
        case .held: return "Plugged in, charging on hold"
        case .discharging: return "On battery"
        }
    }
}

/// Everything read from the battery controller at one instant, in base SI units.
public struct PowerSnapshot: Equatable, Sendable {
    public var date: Date
    public var percent: Int
    public var state: ChargeState
    public var isExternalPower: Bool
    public var minutesToFull: Int?
    public var minutesToEmpty: Int?

    public var batteryVolts: Double
    /// Positive while charging, negative while draining.
    public var batteryAmps: Double

    public var inputWatts: Double?
    public var inputVolts: Double?
    public var inputAmps: Double?
    public var systemLoadWatts: Double?
    public var adapterLossWatts: Double?
    public var adapter: AdapterInfo?

    public var temperatureC: Double?
    public var cycleCount: Int?
    public var designCycleCount: Int?
    public var designCapacity: Int?
    public var fullChargeCapacity: Int?
    public var nominalCapacity: Int?
    public var remainingCapacity: Int?
    public var cellVolts: [Double]

    /// What the battery asks the charger for: per-cell voltage and pack current.
    public var requestedCellVolts: Double?
    public var requestedAmps: Double?
    public var notChargingReason: Int
    public var slowChargingReason: Int
    public var thermallyLimitedSeconds: Int?
    /// Energy Mode for the current power source; filled in by the app, not the registry.
    public var energyMode: EnergyMode? = nil
    /// USB devices the Mac is powering; filled in by the app from the USB registry.
    public var peripherals: [Peripheral] = []
    /// Fans and chip temperatures from the SMC; nil where unavailable.
    public var thermals: Thermals? = nil
    /// Lifetime extremes recorded by the battery controller.
    public var lifetime: BatteryLifetime? = nil

    /// On battery the pack is the only source, yet for a few seconds after unplugging the
    /// current still reads as charging. Such a reading is stale, not real.
    public var batteryReadingIsStale: Bool { !isExternalPower && batteryAmps > -0.02 }

    public var batteryWatts: Double {
        if batteryReadingIsStale { return -(systemLoadWatts ?? 0) }
        return batteryVolts * batteryAmps
    }

    /// Power the Mac itself uses. On battery the pack is the only source, so its own reading
    /// keeps both legs of the flow equal; the controller's load figure is a smoothed average.
    public var systemWatts: Double {
        if !isExternalPower { return max(0.0, -batteryWatts) + 0 }
        if let systemLoadWatts, systemLoadWatts > 0 { return systemLoadWatts }
        return max(0, (inputWatts ?? 0) - batteryWatts)
    }

    public var wallWatts: Double? {
        guard let inputWatts, inputWatts > 0 else { return nil }
        return inputWatts + (adapterLossWatts ?? 0)
    }

    /// Charger load as a fraction of what the active profile can deliver.
    public var chargerLoad: Double? {
        guard let inputWatts, let ceiling = adapter?.ceilingWatts, ceiling > 0 else { return nil }
        return inputWatts / ceiling
    }

    /// Power the battery is asking for right now, from its requested voltage and current.
    public var requestedBatteryWatts: Double? {
        guard state == .charging, let v = requestedCellVolts, let a = requestedAmps,
              v > 0, a > 0, !cellVolts.isEmpty else { return nil }
        return v * Double(cellVolts.count) * a
    }

    /// Total the Mac would draw if the charger were not the limit.
    public var demandWatts: Double {
        systemWatts + (requestedBatteryWatts ?? max(0, batteryWatts))
    }

    /// Long-term capacity against design. The nominal figure is steadier than the raw full
    /// charge capacity, which moves with temperature and load.
    public var health: Double? {
        guard let full = nominalCapacity ?? fullChargeCapacity, let design = designCapacity, design > 0 else { return nil }
        return Double(full) / Double(design)
    }

    public var cellSpreadMillivolts: Int? {
        guard let lo = cellVolts.min(), let hi = cellVolts.max(), cellVolts.count > 1 else { return nil }
        return Int(((hi - lo) * 1000).rounded())
    }

    /// The bus the menu bar's volts and amps describe: charger input when plugged in.
    public var busVolts: Double { isExternalPower ? (inputVolts ?? batteryVolts) : batteryVolts }
    public var busAmps: Double {
        if isExternalPower { return inputAmps ?? batteryAmps }
        return batteryVolts > 0 ? abs(batteryWatts) / batteryVolts : abs(batteryAmps)
    }
    public var headlineWatts: Double { isExternalPower ? (inputWatts ?? 0) : systemWatts }

    /// Wattsup's own estimate for when macOS has none (it stops estimating near full): capacity
    /// left to fill over the charge current, or charge left over the drain. Nil when not measurable.
    public var estimatedMinutes: Int? {
        guard let remaining = remainingCapacity, batteryVolts > 0 else { return nil }
        let amps = batteryWatts / batteryVolts
        let hours: Double
        switch state {
        case .charging:
            guard let full = fullChargeCapacity, full > remaining, amps > 0.05 else { return nil }
            hours = Double(full - remaining) / 1000 / amps
        case .discharging:
            guard remaining > 0, amps < -0.05 else { return nil }
            hours = Double(remaining) / 1000 / -amps
        case .full, .held:
            return nil
        }
        let minutes = Int((hours * 60).rounded())
        return minutes > 0 && minutes < 48 * 60 ? minutes : nil
    }

    public var statusLine: String {
        switch state {
        case .charging:
            if let m = minutesToFull { return "Charging, \(Units.duration(minutes: m)) to full" }
            return estimatedMinutes.map { "Charging, about \(Units.duration(minutes: $0)) to full" }
                ?? "Charging, estimating time"
        case .discharging:
            if let m = minutesToEmpty { return "On battery, \(Units.duration(minutes: m)) left" }
            return estimatedMinutes.map { "On battery, about \(Units.duration(minutes: $0)) left" }
                ?? "On battery, estimating time"
        case .full, .held:
            return state.title
        }
    }
}

public extension PowerSnapshot {
    /// Parses the AppleSmartBattery registry entry. Nil when it has no charge reading.
    init?(registry d: [String: Any], date: Date = Date()) {
        guard let current = d.int("CurrentCapacity") else { return nil }
        let maxValue = d.int("MaxCapacity") ?? 100
        let pct = maxValue > 0 ? Double(current) / Double(maxValue) * 100 : Double(current)

        let external = d.bool("ExternalConnected") ?? false
        let charging = d.bool("IsCharging") ?? false
        let full = d.bool("FullyCharged") ?? false
        let state: ChargeState = !external ? .discharging : full ? .full : charging ? .charging : .held

        let telemetry = d.dict("PowerTelemetryData") ?? [:]
        let battery = d.dict("BatteryData") ?? [:]
        let charger = d.dict("ChargerData") ?? [:]

        self.init(
            date: date,
            percent: min(100, max(0, Int(pct.rounded()))),
            state: state,
            isExternalPower: external,
            minutesToFull: state == .charging
                ? Self.minutes(d.int("AvgTimeToFull")) ?? Self.minutes(d.int("TimeRemaining")) : nil,
            minutesToEmpty: state == .discharging
                ? Self.minutes(d.int("AvgTimeToEmpty")) ?? Self.minutes(d.int("TimeRemaining")) : nil,
            batteryVolts: d.milli("Voltage") ?? 0,
            batteryAmps: d.milli("InstantAmperage", signed: true) ?? d.milli("Amperage", signed: true) ?? 0,
            inputWatts: external ? telemetry.milli("SystemPowerIn", signed: true) : nil,
            inputVolts: external ? telemetry.milli("SystemVoltageIn", signed: true) : nil,
            inputAmps: external ? telemetry.milli("SystemCurrentIn", signed: true) : nil,
            systemLoadWatts: telemetry.milli("SystemLoad", signed: true),
            adapterLossWatts: external ? telemetry.milli("AdapterEfficiencyLoss", signed: true) : nil,
            adapter: external ? d.dict("AdapterDetails").flatMap(Self.adapter) : nil,
            temperatureC: d.int("Temperature").map { Double($0) / 100 },
            cycleCount: d.int("CycleCount"),
            designCycleCount: d.int("DesignCycleCount9C"),
            designCapacity: d.int("DesignCapacity"),
            fullChargeCapacity: d.int("AppleRawMaxCapacity"),
            nominalCapacity: d.int("NominalChargeCapacity"),
            remainingCapacity: d.int("AppleRawCurrentCapacity"),
            cellVolts: battery.ints("CellVoltage").filter { $0 > 0 }.map { Double($0) / 1000 },
            requestedCellVolts: charger.milli("ChargingVoltage"),
            requestedAmps: charger.milli("ChargingCurrent"),
            notChargingReason: charger.int("NotChargingReason") ?? 0,
            slowChargingReason: charger.int("SlowChargingReason") ?? 0,
            thermallyLimitedSeconds: charger.int("TimeChargingThermallyLimited")
        )
        lifetime = (battery.dict("LifetimeData") ?? d.dict("LifetimeData")).flatMap(BatteryLifetime.init)
    }

    /// The controller reports 65535 while estimating and 0 when it has no figure.
    static func minutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }

    static func adapter(_ a: [String: Any]) -> AdapterInfo? {
        let profiles = a.dicts("UsbHvcMenu").compactMap { p -> PDProfile? in
            guard let i = p.int("Index"), let v = p.milli("MaxVoltage"), let c = p.milli("MaxCurrent") else { return nil }
            return PDProfile(index: i, volts: v, amps: c)
        }
        let info = AdapterInfo(
            name: a.string("Name"),
            manufacturer: a.string("Manufacturer"),
            ratedWatts: a.int("Watts").flatMap { $0 > 0 ? $0 : nil },
            negotiatedVolts: a.milli("AdapterVoltage"),
            negotiatedAmps: a.milli("Current"),
            isWireless: a.bool("IsWireless") ?? false,
            profiles: profiles.sorted { $0.index < $1.index },
            activeProfileIndex: a.int("UsbHvcHvcIndex"),
            familyCode: a.signed("FamilyCode"),
            serial: a.string("SerialString") ?? a.string("SerialNumber")
        )
        return info.ratedWatts == nil && info.profiles.isEmpty && info.name == nil ? nil : info
    }
}
