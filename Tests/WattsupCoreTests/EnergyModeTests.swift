import XCTest
@testable import WattsupCore

final class EnergyModeTests: XCTestCase {
    // Captured from a 16 inch M3 Pro, which has no High Power Mode
    let lowPowerOnly = """
    Battery Power:
     lowpowermode         1
     displaysleep         2
    AC Power:
     lowpowermode         0
     displaysleep         10
    """

    let withPowerMode = """
    Battery Power:
     powermode            1
    AC Power:
     powermode            2
    """

    func testParsesLowPowerKey() {
        let m = EnergyModes.parse(pmsetCustom: lowPowerOnly)
        XCTAssertEqual(m.battery, .low)
        XCTAssertEqual(m.charger, .automatic)
        XCTAssertFalse(m.usesPowerModeKey)
        XCTAssertEqual(m.available, [.automatic, .low])
        XCTAssertEqual(m.pmsetArguments(.low, for: .charger), ["-c", "lowpowermode", "1"])
        XCTAssertEqual(m.pmsetArguments(.automatic, for: .battery), ["-b", "lowpowermode", "0"])
    }

    func testParsesPowerModeKeyWithHighPower() {
        let m = EnergyModes.parse(pmsetCustom: withPowerMode)
        XCTAssertEqual(m.battery, .low)
        XCTAssertEqual(m.charger, .high)
        XCTAssertEqual(m.available, [.automatic, .low, .high])
        XCTAssertEqual(m.pmsetArguments(.high, for: .charger), ["-c", "powermode", "2"])
    }

    func testEmptyOutputHasNoModes() {
        let m = EnergyModes.parse(pmsetCustom: "")
        XCTAssertNil(m.battery)
        XCTAssertNil(m.charger)
    }

    func testAutomaticHidesFromMenuBar() {
        XCTAssertNil(EnergyMode.automatic.shortTitle)
        XCTAssertEqual(EnergyMode.low.shortTitle, "Low")
    }
}

final class EnergyModeMetricTests: XCTestCase {
    func testMenuBarReadingAppearsOnlyWhenNotAutomatic() {
        var s = Fixture.snapshot(Fixture.charging())
        XCTAssertNil(MenuBarMetric.energyMode.text(for: s), "unknown mode shows nothing")
        s.energyMode = .automatic
        XCTAssertNil(MenuBarMetric.energyMode.text(for: s))
        s.energyMode = .low
        XCTAssertEqual(MenuBarMetric.energyMode.text(for: s), "Low")
        XCTAssertEqual(MenuBarMetric.energyMode.tone(for: s), .charging)
    }
}
