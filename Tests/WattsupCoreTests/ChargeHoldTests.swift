import XCTest
@testable import WattsupCore

final class ChargeHoldTests: XCTestCase {
    func held(_ percent: Int, code: Int = 0x400001) -> PowerSnapshot {
        var d = Fixture.charging()
        d["IsCharging"] = false
        d["CurrentCapacity"] = percent
        var charger = d["ChargerData"] as! [String: Any]
        charger["NotChargingReason"] = code
        d["ChargerData"] = charger
        return Fixture.snapshot(d)
    }

    func testEightyPercentNamesTheLikelyCauses() throws {
        let h = try XCTUnwrap(ChargeHold(snapshot: held(80)))
        XCTAssertEqual(h.title, "Held at 80%")
        XCTAssertTrue(h.detail.contains("Optimized Battery Charging"))
        XCTAssertEqual(h.code, 0x400001)
    }

    func testFullAndOtherPauses() throws {
        XCTAssertEqual(try XCTUnwrap(ChargeHold(snapshot: held(100))).title, "Full")
        XCTAssertEqual(try XCTUnwrap(ChargeHold(snapshot: held(55))).title, "Charging paused at 55%")
    }

    func testChargingOrOnBatteryHasNoHold() {
        XCTAssertNil(ChargeHold(snapshot: Fixture.snapshot(Fixture.charging())))
        XCTAssertNil(ChargeHold(snapshot: Fixture.snapshot(Fixture.discharging())))
    }
}
