import XCTest
@testable import WattsupCore

final class AccessoryBatteryTests: XCTestCase {
    func testParsesAirPodsFromBluetoothProfile() throws {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"My AirPods Pro 2":{"device_batteryLevelCase":"100%",
        "device_batteryLevelLeft":"94%","device_batteryLevelRight":"89%","device_minorType":"Headphones"}},
        {"Speaker":{"device_minorType":"Speaker"}}],"device_not_connected":[{"Old":{"device_batteryLevelMain":"5%"}}]}]}
        """
        let list = AccessoryBattery.parse(bluetoothJSON: Data(json.utf8))
        XCTAssertEqual(list.count, 1, "devices without a level and disconnected ones are skipped")
        let pods = try XCTUnwrap(list.first)
        XCTAssertEqual(pods.summary, "Left 94%, Right 89%, Case 100%")
        XCTAssertEqual(pods.lowest, 89)
        XCTAssertEqual(pods.symbolName, "airpodspro")
    }

    func testHIDDeviceAndInternalOnesSkipped() {
        XCTAssertEqual(AccessoryBattery(hid: ["Product": "Magic Keyboard", "BatteryPercent": 57])?.summary, "57%")
        XCTAssertNil(AccessoryBattery(hid: ["Product": "Apple Internal Keyboard / Trackpad", "BatteryPercent": 100]))
        XCTAssertNil(AccessoryBattery(hid: ["Product": "Thing"]))
    }

    func testMalformedJSONIsEmpty() {
        XCTAssertTrue(AccessoryBattery.parse(bluetoothJSON: Data("nope".utf8)).isEmpty)
    }
}
