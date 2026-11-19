import XCTest
@testable import WattsupCore

final class ChargerQualityTests: XCTestCase {
    /// Samples on the 45 W fixture charger with input current stepping from 1.0 to 2.2 A and the
    /// voltage falling 0.2 V per amp, as a 0.2 ohm cable would.
    func samples(ohms: Double = 0.2, count: Int = 30, demand: Double = 40) -> (AdapterInfo, [PowerSample]) {
        let base = Fixture.snapshot(Fixture.charging())
        let adapter = base.adapter!
        var out: [PowerSample] = []
        for i in 0..<count {
            let amps = 1.0 + 1.2 * Double(i) / Double(count - 1)
            var d = Fixture.charging(input: Int(amps * (20 - ohms * amps) * 1000))
            var telemetry = d["PowerTelemetryData"] as! [String: Any]
            telemetry["SystemCurrentIn"] = Int(amps * 1000)
            telemetry["SystemVoltageIn"] = Int((20 - ohms * amps) * 1000)
            d["PowerTelemetryData"] = telemetry
            var s = PowerSample(Fixture.snapshot(d, at: Double(i) * 2))
            s.demandWatts = demand
            out.append(s)
        }
        return (adapter, out)
    }

    func testRecoversCableResistanceFromSlope() throws {
        let (adapter, s) = samples(ohms: 0.2)
        let q = ChargerQuality(adapter: adapter, samples: s, dropouts: 0, thermallyLimitedSeconds: 0)
        XCTAssertEqual(try XCTUnwrap(q.resistanceOhms), 0.2, accuracy: 0.01)
        XCTAssertEqual(q.checks.first { $0.name == "Cable resistance" }?.grade, .good)
    }

    func testSagMeasuredUnderLoad() throws {
        let (adapter, s) = samples(ohms: 0.2)
        let q = ChargerQuality(adapter: adapter, samples: s, dropouts: 0, thermallyLimitedSeconds: 0)
        // Loaded samples sit around 1.7 to 2.2 A, so about 0.4 V below 20 V
        XCTAssertEqual(try XCTUnwrap(q.sagFraction), 0.019, accuracy: 0.004)
    }

    func testNotEnoughDataIsUngradedNotPoor() {
        let (adapter, s) = samples(count: 5, demand: 10)
        let q = ChargerQuality(adapter: adapter, samples: s, dropouts: 0, thermallyLimitedSeconds: 0)
        XCTAssertNil(q.resistanceOhms)
        XCTAssertNil(q.checks.first { $0.name == "Cable resistance" }?.grade)
        XCTAssertNil(q.checks.first { $0.name == "Delivers its rating" }?.grade, "never pushed past its limit")
        XCTAssertEqual(q.overall, .excellent, "connection and heat are always measurable")
    }

    func testWeakestLinkSetsOverall() {
        let (adapter, s) = samples(ohms: 0.6)
        let q = ChargerQuality(adapter: adapter, samples: s, dropouts: 4, thermallyLimitedSeconds: 120)
        XCTAssertEqual(q.overall, .poor)
    }

    func testSlope() {
        XCTAssertEqual(ChargerQuality.slope(x: [1, 2, 3], y: [10, 8, 6])!, -2, accuracy: 1e-9)
        XCTAssertNil(ChargerQuality.slope(x: [1, 1], y: [2, 3]))
    }
}
