import Foundation

/// Lifetime extremes the battery's own controller records, from BatteryData.LifetimeData.
public struct BatteryLifetime: Equatable, Sendable {
    public var maxDischargeAmps: Double?
    public var maxChargeAmps: Double?
    public var minPackVolts: Double?
    public var maxPackVolts: Double?
    public var minTempC: Double?
    public var maxTempC: Double?
    public var averageTempC: Double?
    public var operatingHours: Int?

    init?(_ d: [String: Any]) {
        maxDischargeAmps = d.milli("MaximumDischargeCurrent", signed: true).map(abs)
        maxChargeAmps = d.milli("MaximumChargeCurrent")
        minPackVolts = d.milli("MinimumPackVoltage")
        maxPackVolts = d.milli("MaximumPackVoltage")
        minTempC = d.int("MinimumTemperature").map(Double.init)
        maxTempC = d.int("MaximumTemperature").map(Double.init)
        averageTempC = d.int("AverageTemperature").map { Double($0) / 10 }
        operatingHours = d.int("TotalOperatingTime")
        if maxDischargeAmps == nil && maxChargeAmps == nil && operatingHours == nil { return nil }
    }
}

public extension PowerSnapshot {
    /// Rated nominal voltage of one lithium polymer cell. The controller reports charge in mAh
    /// only, so energy is charge times this rating, an estimate within a few percent.
    static let nominalCellVolts = 3.85

    var nominalPackVolts: Double? { cellVolts.isEmpty ? nil : Double(cellVolts.count) * Self.nominalCellVolts }

    /// Energy the battery holds when full today, and was designed to hold, in watt hours.
    var fullEnergyWh: Double? { energy(nominalCapacity ?? fullChargeCapacity) }
    var designEnergyWh: Double? { energy(designCapacity) }
    var remainingEnergyWh: Double? { energy(remainingCapacity) }

    /// Hours the stored energy lasts at the present draw, while on battery.
    var runtimeHoursAtCurrentDraw: Double? {
        guard !isExternalPower, let wh = remainingEnergyWh, systemWatts > 1 else { return nil }
        return wh / systemWatts
    }

    /// Highest power the battery has delivered, from its recorded peak current.
    var peakDischargeWatts: Double? {
        guard let a = lifetime?.maxDischargeAmps, let v = nominalPackVolts else { return nil }
        return a * v
    }

    private func energy(_ mAh: Int?) -> Double? {
        guard let mAh, let v = nominalPackVolts else { return nil }
        return Double(mAh) / 1000 * v
    }
}
