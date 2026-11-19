import XCTest
@testable import WattsupCore

final class ChargerTests: XCTestCase {
    func testPeggedChargerIsBottleneck() {
        let d = Fixture.charging()
        let h = Fixture.history(d, count: 40)
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000), history: h)
        XCTAssertEqual(a.verdict, .bottleneck)
        // Demand is about 61.8 W, plus 10% headroom lands on 70 W
        XCTAssertEqual(a.suggestedWatts, 70)
        XCTAssertTrue(a.detail.contains("96%"), a.detail)
    }

    func testDrainingWhilePluggedInCannotKeepUp() {
        let d = Fixture.charging(input: 44000, battery: -900, load: 55000)
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000),
                                  history: Fixture.history(d, count: 40))
        XCTAssertEqual(a.verdict, .notKeepingUp)
        XCTAssertNotNil(a.suggestedWatts)
    }

    func testLightLoadHasHeadroomAndSuggestsLighterBrick() {
        var d = Fixture.charging(input: 9000, battery: 0, load: 9000)
        d["IsCharging"] = false
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000),
                                  history: Fixture.history(d, count: 40))
        XCTAssertEqual(a.verdict, .headroom)
        XCTAssertNil(a.suggestedWatts)
        XCTAssertTrue(a.advisories.contains { $0.contains("lighter 30 W") }, "\(a.advisories)")
    }

    func testTooFewSamplesKeepsMeasuring() {
        let d = Fixture.charging()
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000),
                                  history: Fixture.history(d, count: 5))
        XCTAssertEqual(a.verdict, .measuring)
    }

    func testUnplugged() {
        let d = Fixture.discharging()
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d), history: PowerHistory())
        XCTAssertEqual(a.verdict, .unplugged)
    }

    func testCableCapAdvisory() {
        var d = Fixture.charging()
        var adapter = Fixture.adapter45
        adapter["Current"] = 1500
        d["AdapterDetails"] = adapter
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000),
                                  history: Fixture.history(d, count: 40))
        XCTAssertTrue(a.advisories.contains { $0.contains("cable") }, "\(a.advisories)")
    }

    func testSuggestedSizes() {
        XCTAssertEqual(ChargerAssessment.suggestedSize(forDemand: 25), 30)
        XCTAssertEqual(ChargerAssessment.suggestedSize(forDemand: 58), 65)
        XCTAssertEqual(ChargerAssessment.suggestedSize(forDemand: 200), 140)
    }

    func testHistoryTrimsToWindow() {
        var h = PowerHistory(window: 10)
        let d = Fixture.charging()
        for t in stride(from: 0.0, through: 30, by: 2) { h.append(Fixture.snapshot(d, at: t)) }
        XCTAssertEqual(h.samples.first?.date, Date(timeIntervalSinceReferenceDate: 20))
        h.append(Fixture.snapshot(d, at: 5))
        XCTAssertEqual(h.samples.count, 1, "a clock jump backwards resets the window")
    }

    func testChargerLogAccumulatesTimeAndPeaks() throws {
        var log = ChargerLog()
        log.record(Fixture.snapshot(Fixture.charging(input: 30000), at: 0), verdict: nil)
        log.record(Fixture.snapshot(Fixture.charging(input: 43020), at: 2), verdict: "bottleneck")
        log.record(Fixture.snapshot(Fixture.charging(input: 20000), at: 500), verdict: nil)
        let r = try XCTUnwrap(log.records.first)
        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(r.secondsConnected, 2, "the 498 s gap counts as unplugged")
        XCTAssertEqual(r.peakInputWatts, 43.02, accuracy: 0.001)
        XCTAssertEqual(r.lastVerdict, "bottleneck")
        log.record(Fixture.snapshot(Fixture.discharging(), at: 600), verdict: nil)
        XCTAssertEqual(log.records.count, 1, "battery readings are not chargers")
    }
}
