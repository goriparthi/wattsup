import Foundation
@testable import WattsupCore

// Registry shapes captured from a 16 inch MacBook Pro on a 45 W USB-C charger.
enum Fixture {
    static func charging(input: Int = 43020, battery: Int = 2124, load: Int = 15857) -> [String: Any] {
        [
            "CurrentCapacity": 89, "MaxCapacity": 100,
            "ExternalConnected": true, "IsCharging": true, "FullyCharged": false,
            "AvgTimeToFull": 47, "AvgTimeToEmpty": 65535, "TimeRemaining": 47,
            "Voltage": 12789, "InstantAmperage": NSNumber(value: Int64(battery)),
            "Temperature": 3057, "CycleCount": 245, "DesignCycleCount9C": 1000,
            "DesignCapacity": 8579, "AppleRawMaxCapacity": 8054,
            "NominalChargeCapacity": 8298, "AppleRawCurrentCapacity": 7159,
            "AdapterDetails": adapter45,
            "PowerTelemetryData": [
                "SystemPowerIn": input, "SystemLoad": load, "SystemVoltageIn": 19630,
                "SystemCurrentIn": 2192, "AdapterEfficiencyLoss": 1183,
            ] as [String: Any],
            "BatteryData": ["CellVoltage": [4264, 4259, 4265]] as [String: Any],
            "ChargerData": [
                "ChargingVoltage": 4310, "ChargingCurrent": 3551, "NotChargingReason": 0,
                "SlowChargingReason": 0, "TimeChargingThermallyLimited": 0,
            ] as [String: Any],
        ]
    }

    static func discharging(amps: Int64 = -1500) -> [String: Any] {
        var d = charging()
        d["ExternalConnected"] = false
        d["IsCharging"] = false
        d["AvgTimeToEmpty"] = 190
        d["AvgTimeToFull"] = 65535
        // ioreg stores negative currents as unsigned 64 bit patterns
        d["InstantAmperage"] = NSNumber(value: UInt64(bitPattern: amps))
        d["Voltage"] = 12400
        d["PowerTelemetryData"] = ["SystemPowerIn": 0, "SystemLoad": 18600] as [String: Any]
        return d
    }

    static let adapter45: [String: Any] = [
        "IsWireless": false, "AdapterVoltage": 20000, "Watts": 45, "Current": 2250,
        "UsbHvcHvcIndex": 4, "FamilyCode": NSNumber(value: UInt64(18446744073172697098)),
        "UsbHvcMenu": [
            ["Index": 0, "MaxCurrent": 3000, "MaxVoltage": 5000],
            ["Index": 1, "MaxCurrent": 3000, "MaxVoltage": 9000],
            ["Index": 2, "MaxCurrent": 3000, "MaxVoltage": 12000],
            ["Index": 3, "MaxCurrent": 3000, "MaxVoltage": 15000],
            ["Index": 4, "MaxCurrent": 2250, "MaxVoltage": 20000],
        ],
    ]

    static func snapshot(_ d: [String: Any], at seconds: TimeInterval = 0) -> PowerSnapshot {
        PowerSnapshot(registry: d, date: Date(timeIntervalSinceReferenceDate: seconds))!
    }

    /// A history of identical readings every 2 s ending at `end`.
    static func history(_ d: [String: Any], count: Int, end: TimeInterval = 1000) -> PowerHistory {
        var h = PowerHistory()
        for i in 0..<count {
            h.append(snapshot(d, at: end - Double(count - 1 - i) * 2))
        }
        return h
    }
}
