import XCTest
@testable import WattsupCore

final class BatteryEnergyTests: XCTestCase {
    func withLifetime() -> PowerSnapshot {
        var d = Fixture.charging()
        var battery = d["BatteryData"] as! [String: Any]
        battery["LifetimeData"] = [
            "MaximumDischargeCurrent": NSNumber(value: UInt64(18446744073709543581)), "MaximumChargeCurrent": 9794,
            "MinimumPackVoltage": 9110, "MaximumPackVoltage": 13154, "MinimumTemperature": 9,
            "MaximumTemperature": 45, "AverageTemperature": 237, "TotalOperatingTime": 23066,
        ] as [String: Any]
        d["BatteryData"] = battery
        return Fixture.snapshot(d)
    }

    func testEnergyFromChargeAndNominalVoltage() throws {
        let s = withLifetime()
        // 3 cells at 3.85 V is 11.55 V; 8579 mAh design is about 99.1 Wh, close to Apple's 100 Wh rating
        XCTAssertEqual(try XCTUnwrap(s.designEnergyWh), 8.579 * 11.55, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(s.fullEnergyWh), 8.298 * 11.55, accuracy: 0.01)
        XCTAssertNil(s.runtimeHoursAtCurrentDraw, "no runtime estimate while on the charger")
    }

    func testLifetimeAndPeakPower() throws {
        let s = withLifetime()
        let life = try XCTUnwrap(s.lifetime)
        XCTAssertEqual(try XCTUnwrap(life.maxDischargeAmps), 8.035, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(life.averageTempC), 23.7, accuracy: 0.001)
        XCTAssertEqual(life.operatingHours, 23066)
        XCTAssertEqual(try XCTUnwrap(s.peakDischargeWatts), 8.035 * 11.55, accuracy: 0.01)
    }

    func testRuntimeOnBattery() throws {
        let s = Fixture.snapshot(Fixture.discharging(amps: -1500))
        // 7159 mAh at 11.55 V is about 82.7 Wh; at 18.6 W that is about 4.4 hours
        XCTAssertEqual(try XCTUnwrap(s.runtimeHoursAtCurrentDraw), 7.159 * 11.55 / 18.6, accuracy: 0.01)
    }
}
