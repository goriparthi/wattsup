import XCTest
@testable import WattsupCore

final class MenuBarAndVersionTests: XCTestCase {
    func testTonesFollowState() {
        let charging = Fixture.snapshot(Fixture.charging())
        XCTAssertEqual(MenuBarMetric.watts.tone(for: charging), .input)
        XCTAssertEqual(MenuBarMetric.chargerLoad.tone(for: charging), .warning, "96% load")
        XCTAssertEqual(MenuBarMetric.batteryWatts.tone(for: charging), .charging)
        let battery = Fixture.snapshot(Fixture.discharging())
        XCTAssertEqual(MenuBarMetric.watts.tone(for: battery), .draining)
        XCTAssertEqual(MenuBarMetric.batteryWatts.tone(for: battery), .draining)
        XCTAssertNil(MenuBarMetric.chargerLoad.text(for: battery), "no charger, no reading")
    }

    func testRowsSplitTopHeavy() {
        XCTAssertEqual(MenuBarMetric.rows([.watts, .volts, .amps]), [[.watts, .volts], [.amps]])
        XCTAssertEqual(MenuBarMetric.rows([.watts]), [[.watts]])
    }

    func testCompleteOrderKeepsSavedAndAppendsNew() {
        let order = MenuBarMetric.completeOrder([.amps, .watts])
        XCTAssertEqual(Array(order.prefix(2)), [.amps, .watts])
        XCTAssertEqual(Set(order), Set(MenuBarMetric.allCases))
        XCTAssertEqual(order.count, MenuBarMetric.allCases.count)
        XCTAssertEqual(Array(MenuBarMetric.defaultOrder.prefix(4)), MenuBarMetric.defaults)
    }

    func testDecodeKeepsOrderAndDropsRepeats() {
        XCTAssertEqual(MenuBarMetric.decode("amps,watts,amps,nope"), [.amps, .watts])
    }

    func testVersionOrdering() {
        XCTAssertTrue(VersionCompare.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(VersionCompare.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(VersionCompare.isNewer("0.2.0", than: "0.2.0-beta.3"))
        XCTAssertFalse(VersionCompare.isNewer("0.1.0", than: "0.1.0"))
    }
}

final class SparklineMetricTests: XCTestCase {
    func testHiddenUntilThereIsAMinuteToDraw() {
        var s = Fixture.snapshot(Fixture.charging())
        XCTAssertNil(MenuBarMetric.sparkline.text(for: s), "no history yet, nothing in the menu bar")
        s.recentWatts = [20, 35, 28]
        XCTAssertEqual(MenuBarMetric.sparkline.text(for: s), "20 to 35 W over 60 s")
        XCTAssertEqual(MenuBarMetric.sparkline.tone(for: s), .input)
    }
}
