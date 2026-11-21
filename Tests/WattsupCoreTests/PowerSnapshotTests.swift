import XCTest
@testable import WattsupCore

final class PowerSnapshotTests: XCTestCase {
    func testParsesChargingReading() throws {
        let s = Fixture.snapshot(Fixture.charging())
        XCTAssertEqual(s.percent, 89)
        XCTAssertEqual(s.state, .charging)
        XCTAssertEqual(s.minutesToFull, 47)
        XCTAssertNil(s.minutesToEmpty)
        XCTAssertEqual(s.batteryWatts, 12.789 * 2.124, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.inputWatts), 43.02, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, 15.857, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.wallWatts), 44.203, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.temperatureC), 30.57, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.health), 8298.0 / 8579.0, accuracy: 0.0001)
        XCTAssertEqual(s.cellVolts, [4.264, 4.259, 4.265])
        XCTAssertEqual(s.cellSpreadMillivolts, 6)
    }

    func testParsesAdapterAndProfiles() throws {
        let a = try XCTUnwrap(Fixture.snapshot(Fixture.charging()).adapter)
        XCTAssertEqual(a.ratedWatts, 45)
        XCTAssertEqual(a.profiles.count, 5)
        XCTAssertEqual(a.activeProfile?.volts, 20)
        XCTAssertEqual(try XCTUnwrap(a.ceilingWatts), 45, accuracy: 0.001)
        XCTAssertEqual(a.title, "45 W USB-C charger")
        XCTAssertEqual(a.familyCode, -536854518)
    }

    func testRequestedPowerUsesCellCountAndCurrent() throws {
        let s = Fixture.snapshot(Fixture.charging())
        // 4.31 V per cell, 3 cells, 3.551 A
        XCTAssertEqual(try XCTUnwrap(s.requestedBatteryWatts), 4.31 * 3 * 3.551, accuracy: 0.001)
        XCTAssertEqual(s.demandWatts, 15.857 + 4.31 * 3 * 3.551, accuracy: 0.001)
    }

    func testNegativeCurrentStoredAsUnsignedBitPattern() {
        let s = Fixture.snapshot(Fixture.discharging(amps: -1500))
        XCTAssertEqual(s.batteryAmps, -1.5, accuracy: 0.0001)
        XCTAssertEqual(s.state, .discharging)
        XCTAssertEqual(s.minutesToEmpty, 190)
        XCTAssertNil(s.adapter)
        XCTAssertNil(s.inputWatts)
        XCTAssertEqual(s.headlineWatts, 12.4 * 1.5, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, -s.batteryWatts, accuracy: 0.0001, "on battery both legs agree")
        XCTAssertEqual(s.busAmps, 1.5, accuracy: 0.0001)
    }

    func testStaleChargingCurrentRightAfterUnplugging() {
        // The plug flag flips first; the current still reads +2.124 A for a few seconds
        let s = Fixture.snapshot(Fixture.discharging(amps: 2124))
        XCTAssertTrue(s.batteryReadingIsStale)
        XCTAssertEqual(s.batteryWatts, -18.6, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, 18.6, accuracy: 0.001, "never 0 W on battery")
        XCTAssertEqual(s.busAmps, 18.6 / 12.4, accuracy: 0.001)
        XCTAssertEqual(MenuBarMetric.batteryWatts.tone(for: s), .draining)
    }

    func testNoNegativeZeroAndZeroCurrentOnBatteryUsesLoad() {
        let s = Fixture.snapshot(Fixture.discharging(amps: 0))
        XCTAssertEqual(s.systemWatts, 18.6, accuracy: 0.001, "zero current right after unplugging falls back to the load")
        XCTAssertEqual(MenuBarMetric.systemWatts.text(for: s), "18.6W")
        XCTAssertEqual(Units.clean(-0.04), 0)
        XCTAssertEqual(String(format: "%.1f", Units.clean(-0.0)), "0.0")
    }

    func testWattsupEstimatesWhenMacOSStops() {
        var d = Fixture.charging()
        d["AvgTimeToFull"] = 65535
        d["TimeRemaining"] = 0
        let s = Fixture.snapshot(d)
        XCTAssertNil(s.minutesToFull)
        // (8054 - 7159) mAh at 2.124 A is about 25 minutes
        XCTAssertEqual(s.estimatedMinutes, 25)
        XCTAssertEqual(s.statusLine, "Charging, about 25 min to full")
        XCTAssertEqual(MenuBarMetric.time.text(for: s), "~0:25")
    }

    func testTimeReadingNeverVanishes() {
        var d = Fixture.charging()
        d["AvgTimeToFull"] = 65535
        d["TimeRemaining"] = 0
        d["IsCharging"] = false
        XCTAssertEqual(MenuBarMetric.time.text(for: Fixture.snapshot(d)), "Held")
        d["FullyCharged"] = true
        XCTAssertEqual(MenuBarMetric.time.text(for: Fixture.snapshot(d)), "Full")
        var e = Fixture.charging()
        e["AvgTimeToFull"] = 65535
        e["TimeRemaining"] = 0
        e["AppleRawCurrentCapacity"] = 8054
        XCTAssertEqual(MenuBarMetric.time.text(for: Fixture.snapshot(e)), "…", "nothing to fill yet")
    }

    func testPluggedInNotChargingIsHeld() {
        var d = Fixture.charging()
        d["IsCharging"] = false
        XCTAssertEqual(Fixture.snapshot(d).state, .held)
        d["FullyCharged"] = true
        XCTAssertEqual(Fixture.snapshot(d).state, .full)
    }

    func testSystemWattsFallsBackToDifference() {
        var d = Fixture.charging()
        d["PowerTelemetryData"] = ["SystemPowerIn": 43020] as [String: Any]
        let s = Fixture.snapshot(d)
        XCTAssertEqual(s.systemWatts, 43.02 - 12.789 * 2.124, accuracy: 0.001)
    }

    func testFastChargingBalancesWhenSystemLoadDisagrees() {
        // Seen on a 16 inch MacBook Pro at 59%: SystemLoad 82.5 W while the pack took 70.7 W of 87 W
        var d = Fixture.charging()
        d["Voltage"] = 12246
        d["InstantAmperage"] = NSNumber(value: Int64(5774))
        d["PowerTelemetryData"] = ["SystemPowerIn": 86957, "SystemLoad": 82533] as [String: Any]
        let s = Fixture.snapshot(d)
        XCTAssertEqual(s.batteryWatts, 12.246 * 5.774, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, 86.957 - 12.246 * 5.774, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts + s.batteryWatts, 86.957, accuracy: 0.001, "the flow balances")
    }

    func testMissingChargeReadingIsNil() {
        XCTAssertNil(PowerSnapshot(registry: ["Voltage": 12000]))
    }

    func testMenuBarLine() {
        let s = Fixture.snapshot(Fixture.charging())
        XCTAssertEqual(MenuBarMetric.line(MenuBarMetric.defaults, for: s), "44.2W 96% 15.9W 89%")
        XCTAssertEqual(MenuBarMetric.line([.watts, .volts, .amps], for: s), "43.0W 19.63V 2.19A")
        let battery = Fixture.snapshot(Fixture.discharging())
        XCTAssertEqual(MenuBarMetric.line(MenuBarMetric.defaults, for: battery), "18.6W 89%")
        XCTAssertEqual(MenuBarMetric.line([.percent, .time, .chargerLoad], for: s), "89% 0:47 96%")
        XCTAssertEqual(MenuBarMetric.decode("watts,bogus,amps"), [.watts, .amps])
    }

    func testSeenTimestamps() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let en = Locale(identifier: "en_US")
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
        func at(_ d: Int, _ h: Int, _ m: Int, year: Int = 2026) -> Date {
            cal.date(from: DateComponents(year: year, month: 11, day: d, hour: h, minute: m))!
        }
        func norm(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(norm(Units.seen(at(20, 8, 5), now: now, calendar: cal, locale: en)), "Today 8:05 AM")
        XCTAssertEqual(norm(Units.seen(at(19, 16, 12), now: now, calendar: cal, locale: en)), "Yesterday 4:12 PM")
        XCTAssertEqual(norm(Units.seen(at(17, 9, 3), now: now, calendar: cal, locale: en)), "Tue, Nov 17, 9:03 AM")
        XCTAssertTrue(norm(Units.seen(at(17, 9, 3, year: 2025), now: now, calendar: cal, locale: en)).contains("2025"))
    }

    func testUnits() {
        XCTAssertEqual(Units.watts(27.16, signed: true), "+27.2 W")
        XCTAssertEqual(Units.watts(-12.0, signed: true), "\u{2212}12.0 W")
        XCTAssertEqual(Units.amps(-1.5), "\u{2212}1.50 A")
        XCTAssertEqual(Units.watts(0.01, signed: true), "0.0 W")
        XCTAssertEqual(Units.duration(minutes: 65), "1 h 5 min")
        XCTAssertEqual(Units.duration(minutes: 120), "2 h")
        XCTAssertEqual(Units.clock(minutes: 65), "1:05")
    }
}
