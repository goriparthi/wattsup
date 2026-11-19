import XCTest
@testable import WattsupCore

final class PeripheralTests: XCTestCase {
    // Captured from an iPhone on a MacBook Pro USB-C port
    let iPhone: [String: Any] = [
        "USB Product Name": "iPhone", "USB Vendor Name": "Apple Inc.",
        "UsbPowerSinkAllocation": 2400, "UsbPowerSinkCapability": 2400, "locationID": 17825792,
    ]

    func testParsesAllocation() throws {
        let p = try XCTUnwrap(Peripheral(registry: iPhone))
        XCTAssertEqual(p.name, "iPhone")
        XCTAssertEqual(p.allocatedWatts, 12, accuracy: 0.001)
        XCTAssertEqual(p.symbolName, "iphone")
        var case_ = iPhone
        case_["USB Product Name"] = "MagSafe Charging Case (USB-C)"
        XCTAssertEqual(Peripheral(registry: case_)?.symbolName, "airpodspro.chargingcase.wireless.fill")
    }

    func testDeviceWithoutAllocationIsSkipped() {
        var d = iPhone
        d["UsbPowerSinkAllocation"] = 0
        XCTAssertNil(Peripheral(registry: d))
        d.removeValue(forKey: "UsbPowerSinkAllocation")
        XCTAssertNil(Peripheral(registry: d))
    }

    func testTotalsAndMenuBarReading() throws {
        let p = try XCTUnwrap(Peripheral(registry: iPhone))
        var s = Fixture.snapshot(Fixture.discharging())
        XCTAssertNil(MenuBarMetric.peripherals.text(for: s), "nothing plugged in, nothing shown")
        s.peripherals = [p, p]
        XCTAssertEqual(s.peripherals.allocatedWatts, 24, accuracy: 0.001)
        XCTAssertEqual(MenuBarMetric.peripherals.text(for: s), "USB 24W")
    }
}
