import XCTest
@testable import WattsupCore

final class EfficiencyTests: XCTestCase {
    func testRatesFromInputAndLoss() throws {
        // 43.02 W delivered, 1.183 W lost
        let e = try XCTUnwrap(ChargerEfficiency(snapshot: Fixture.snapshot(Fixture.charging())))
        XCTAssertEqual(e.efficiency, 43.02 / 44.203, accuracy: 0.0001)
        XCTAssertEqual(e.grade, .excellent)
        XCTAssertEqual(e.summary, "97% Excellent, 1.2 W lost as heat")
    }

    func testGrades() {
        XCTAssertEqual(ChargerEfficiency.Grade.of(0.95), .excellent)
        XCTAssertEqual(ChargerEfficiency.Grade.of(0.91), .good)
        XCTAssertEqual(ChargerEfficiency.Grade.of(0.86), .fair)
        XCTAssertEqual(ChargerEfficiency.Grade.of(0.80), .poor)
    }

    func testLightLoadAndBatteryAreNotRated() {
        XCTAssertNil(ChargerEfficiency(snapshot: Fixture.snapshot(Fixture.charging(input: 6000))))
        XCTAssertNil(ChargerEfficiency(snapshot: Fixture.snapshot(Fixture.discharging())))
    }

    func testLogAveragesEfficiencyAndOldLogsStillDecode() throws {
        var log = ChargerLog()
        log.record(Fixture.snapshot(Fixture.charging(), at: 0), verdict: nil)
        log.record(Fixture.snapshot(Fixture.charging(), at: 2), verdict: nil)
        let avg = try XCTUnwrap(log.records.first?.averageEfficiency)
        XCTAssertEqual(avg, 43.02 / 44.203, accuracy: 0.0001)

        // A record written before efficiency existed has no such keys
        let old = #"{"records":[{"fingerprint":"x","title":"Old","profiles":[],"firstSeen":0,"lastSeen":0,"secondsConnected":0,"peakInputWatts":10,"peakDemandWatts":10}]}"#
        let decoded = try JSONDecoder().decode(ChargerLog.self, from: Data(old.utf8))
        XCTAssertNil(decoded.records.first?.averageEfficiency)
    }
}
