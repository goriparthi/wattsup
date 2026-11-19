import XCTest
@testable import WattsupCore

final class EnergyAccountTests: XCTestCase {
    func minute(_ t: TimeInterval, wall: Double, mac: Double, battery: Double, plugged: Bool = true) -> PowerSample {
        var s = PowerSample(Fixture.snapshot(Fixture.charging(), at: 0))
        s.date = Date(timeIntervalSince1970: t)
        s.wallWatts = wall; s.systemWatts = mac; s.batteryWatts = battery
        s.isExternalPower = plugged; s.seconds = 60
        return s
    }

    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func testIntegratesWattsOverMinutes() throws {
        // One hour at 60 W from the wall, 40 W used, 20 W into the battery
        let hour = (0..<60).map { minute(Double($0) * 60, wall: 60, mac: 40, battery: 20) }
        let day = try XCTUnwrap(EnergyAccount.daily(hour, calendar: utc).first)
        XCTAssertEqual(day.wallWh, 60, accuracy: 0.001)
        XCTAssertEqual(day.macWh, 40, accuracy: 0.001)
        XCTAssertEqual(day.chargedWh, 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(day.cost(perKWh: 0.30)), 0.018, accuracy: 0.0001)
    }

    func testSplitsByDayAndCountsBatteryDrain() {
        let days = EnergyAccount.daily([
            minute(86400 - 60, wall: 0, mac: 12, battery: -12, plugged: false),
            minute(86400 + 60, wall: 30, mac: 30, battery: 0),
        ], calendar: utc)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].drainedWh, 0.2, accuracy: 0.0001)
        XCTAssertEqual(days[0].wallWh, 0, "on battery nothing comes from the wall")
        XCTAssertEqual(EnergyAccount.total(days).macWh, 0.7, accuracy: 0.0001)
    }

    func testFormat() {
        XCTAssertEqual(EnergyAccount.format(wattHours: 512), "512 Wh")
        XCTAssertEqual(EnergyAccount.format(wattHours: 1520), "1.52 kWh")
    }
}
