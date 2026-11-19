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

    func testFirstSecondsAfterPluggingInAreNegotiation() {
        var h = PowerHistory()
        for i in 0..<5 { h.append(Fixture.snapshot(Fixture.discharging(), at: Double(i) * 2)) }
        let d = Fixture.charging()
        for i in 5..<10 { h.append(Fixture.snapshot(d, at: Double(i) * 2)) }
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 18), history: h)
        XCTAssertEqual(a.verdict, .negotiating, "8 s after plugging in")
        XCTAssertFalse(a.verdict.isSettled)
    }

    func testChargerAlreadyInAtLaunchSkipsNegotiation() {
        let d = Fixture.charging()
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000), history: Fixture.history(d, count: 5))
        XCTAssertEqual(a.verdict, .measuring, "connected before Wattsup started, so no negotiation to wait for")
    }

    func testRampDuringNegotiationIsNeverJudged() {
        // On battery, then plugged in: battery still draining as input ramps, then charging normally
        var h = PowerHistory()
        h.append(Fixture.snapshot(Fixture.discharging(), at: -2))
        for i in 0..<10 { h.append(Fixture.snapshot(Fixture.charging(input: 9000, battery: -900, load: 20000), at: Double(i) * 2)) }
        let good = Fixture.charging(input: 30000, battery: 800, load: 20000)
        for i in 10..<40 { h.append(Fixture.snapshot(good, at: Double(i) * 2)) }
        let a = ChargerAssessment(snapshot: Fixture.snapshot(good, at: 78), history: h)
        XCTAssertNotEqual(a.verdict, .notKeepingUp)
        XCTAssertEqual(a.verdict, .headroom)
    }

    func testTooFewSettledSamplesKeepsMeasuring() {
        var h = PowerHistory()
        h.append(Fixture.snapshot(Fixture.discharging(), at: -2))
        let d = Fixture.charging()
        for i in 0..<16 { h.append(Fixture.snapshot(d, at: Double(i) * 2)) }
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 30), history: h)
        XCTAssertEqual(a.verdict, .measuring, "30 s in, only 5 readings after negotiation")
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

    func testThreeAmpMenuIsFlaggedAsCableCapped() {
        var d = Fixture.charging()
        d["AdapterDetails"] = [
            "Watts": 60, "AdapterVoltage": 20000, "Current": 3000, "UsbHvcHvcIndex": 3,
            "UsbHvcMenu": [
                ["Index": 0, "MaxCurrent": 3000, "MaxVoltage": 5000],
                ["Index": 1, "MaxCurrent": 3000, "MaxVoltage": 9000],
                ["Index": 2, "MaxCurrent": 3000, "MaxVoltage": 15000],
                ["Index": 3, "MaxCurrent": 3000, "MaxVoltage": 20000],
            ],
        ] as [String: Any]
        let adapter = Fixture.snapshot(d).adapter!
        XCTAssertTrue(ChargerAssessment.looksCableCapped(adapter))
        // The 45 W fixture tops out at 2.25 A, which is the charger's own limit, not the cable's
        XCTAssertFalse(ChargerAssessment.looksCableCapped(Fixture.snapshot(Fixture.charging()).adapter!))
    }

    func testTransientNegotiationEntriesArePruned() {
        var log = ChargerLog()
        log.record(Fixture.snapshot(Fixture.charging(), at: 0), verdict: nil)
        log.record(Fixture.snapshot(Fixture.charging(), at: 2), verdict: nil)
        log.pruneTransient(now: Date(timeIntervalSinceReferenceDate: 600))
        XCTAssertEqual(log.records.count, 1, "kept while still recent")
        log.pruneTransient(now: Date(timeIntervalSinceReferenceDate: 4000))
        XCTAssertTrue(log.records.isEmpty, "a 2 second never judged entry is negotiation noise")
        log.record(Fixture.snapshot(Fixture.charging(), at: 0), verdict: "Charger has headroom")
        log.pruneTransient(now: Date(timeIntervalSinceReferenceDate: 9000))
        XCTAssertEqual(log.records.count, 1, "judged chargers are never pruned")
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

final class CableFindingTests: XCTestCase {
    /// A pegged charger whose profiles all stop at 20 V 3 A
    func capped(name: String? = nil) -> [String: Any] {
        var d = Fixture.charging(input: 58500, battery: 2124, load: 30000)
        var adapter: [String: Any] = [
            "Watts": 60, "AdapterVoltage": 20000, "Current": 3000, "UsbHvcHvcIndex": 3,
            "UsbHvcMenu": [
                ["Index": 0, "MaxCurrent": 3000, "MaxVoltage": 5000],
                ["Index": 3, "MaxCurrent": 3000, "MaxVoltage": 20000],
            ],
        ]
        if let name { adapter["Name"] = name }
        d["AdapterDetails"] = adapter
        return d
    }

    func testUnnamedCappedChargerSaysCheckTheCable() {
        let d = capped()
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000), history: Fixture.history(d, count: 40))
        XCTAssertEqual(a.verdict, .bottleneck)
        XCTAssertEqual(a.headline, "Power is capped: check the cable")
        XCTAssertTrue(a.detail.contains("cable is likely the limit"), a.detail)
        XCTAssertTrue(a.advisories.contains { $0.contains("check the cable") }, "\(a.advisories)")
    }

    func testNamedChargerSeenAtHigherPowerProvesTheCable() {
        let earlier = ChargerRecord(
            fingerprint: "other cable", title: "96W USB-C Power Adapter", ratedWatts: 96, ceilingWatts: 96,
            profiles: [PDProfile(index: 0, volts: 20, amps: 4.8)], firstSeen: Date(), lastSeen: Date(),
            secondsConnected: 60, peakInputWatts: 80, peakDemandWatts: 80, lastVerdict: nil)
        let d = capped(name: "96W USB-C Power Adapter")
        let a = ChargerAssessment(snapshot: Fixture.snapshot(d, at: 1000), history: Fixture.history(d, count: 40),
                                  known: [earlier])
        XCTAssertEqual(a.headline, "The cable is the bottleneck")
        XCTAssertTrue(a.detail.contains("96 W on another cable"), a.detail)
    }

    func testUncappedChargerHasNoCableFinding() {
        let d = Fixture.charging()
        XCTAssertEqual(ChargerAssessment.cableFinding(Fixture.snapshot(d).adapter!, known: []), .none)
    }
}
