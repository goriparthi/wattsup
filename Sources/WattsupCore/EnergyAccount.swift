import Foundation

/// Energy over one local calendar day, integrated from stored minutes (watts times seconds).
public struct DayEnergy: Equatable, Sendable, Identifiable {
    public var day: Date
    public var wallWh: Double = 0
    public var macWh: Double = 0
    public var chargedWh: Double = 0
    public var drainedWh: Double = 0
    public var coveredSeconds: Double = 0
    public var id: Date { day }

    public func cost(perKWh price: Double?) -> Double? {
        price.map { wallWh / 1000 * $0 }
    }
}

public enum EnergyAccount {
    /// Groups minutes by local day. Days are cut in the given calendar's time zone, which is
    /// the display layer; samples themselves are stored in UTC.
    public static func daily(_ samples: [PowerSample], calendar: Calendar = .current) -> [DayEnergy] {
        var days: [Date: DayEnergy] = [:]
        for s in samples where s.seconds > 0 {
            let day = calendar.startOfDay(for: s.date)
            var d = days[day] ?? DayEnergy(day: day)
            let hours = s.seconds / 3600
            if s.isExternalPower { d.wallWh += s.wallWatts * hours }
            d.macWh += s.systemWatts * hours
            if s.batteryWatts > 0 { d.chargedWh += s.batteryWatts * hours } else { d.drainedWh += -s.batteryWatts * hours }
            d.coveredSeconds += s.seconds
            days[day] = d
        }
        return days.values.sorted { $0.day < $1.day }
    }

    public static func total(_ days: [DayEnergy]) -> DayEnergy {
        days.reduce(into: DayEnergy(day: days.first?.day ?? Date())) { t, d in
            t.wallWh += d.wallWh; t.macWh += d.macWh; t.chargedWh += d.chargedWh
            t.drainedWh += d.drainedWh; t.coveredSeconds += d.coveredSeconds
        }
    }

    public static func format(wattHours wh: Double) -> String {
        wh >= 1000 ? String(format: "%.2f kWh", wh / 1000) : String(format: "%.0f Wh", wh)
    }
}
