import XCTest
@testable import WattsupCore

final class AlertTests: XCTestCase {
    func engine(_ kinds: Set<AlertKind> = Set(AlertKind.allCases), level: Int = 80) -> AlertEngine {
        AlertEngine(enabled: kinds, chargedLevel: level)
    }

    func snap(_ d: [String: Any], at t: Double) -> PowerSnapshot { Fixture.snapshot(d, at: t) }

    func testHotFiresOnceThenNeedsToCool() {
        var e = engine()
        var hot = Fixture.charging(); hot["Temperature"] = 4100
        var warm = Fixture.charging(); warm["Temperature"] = 3900
        var cool = Fixture.charging(); cool["Temperature"] = 3500
        XCTAssertTrue(e.evaluate(snap(Fixture.charging(), at: 0), assessment: nil).isEmpty, "first reading only primes")
        XCTAssertEqual(e.evaluate(snap(hot, at: 2), assessment: nil).map(\.kind), [.batteryHot])
        XCTAssertTrue(e.evaluate(snap(warm, at: 4), assessment: nil).isEmpty)
        XCTAssertTrue(e.evaluate(snap(hot, at: 6), assessment: nil).isEmpty, "not re-armed until below 37")
        _ = e.evaluate(snap(cool, at: 8), assessment: nil)
        XCTAssertTrue(e.evaluate(snap(hot, at: 10), assessment: nil).isEmpty, "re-armed but inside the cooldown")
        XCTAssertEqual(e.evaluate(snap(hot, at: 10 + AlertEngine.cooldown), assessment: nil).map(\.kind), [.batteryHot])
    }

    func testChargedToLevelOnCrossing() {
        var e = engine(level: 90)
        _ = e.evaluate(snap(Fixture.charging(), at: 0), assessment: nil)
        var at90 = Fixture.charging(); at90["CurrentCapacity"] = 90
        XCTAssertEqual(e.evaluate(snap(at90, at: 2), assessment: nil).first?.title, "Charged to 90%")
    }

    func testDisabledKindsStaySilent() {
        var e = engine([], level: 80)
        var hot = Fixture.charging(); hot["Temperature"] = 4500
        _ = e.evaluate(snap(Fixture.charging(), at: 0), assessment: nil)
        XCTAssertTrue(e.evaluate(snap(hot, at: 2), assessment: nil).isEmpty)
    }

    func testUnpluggedLow() {
        var e = engine()
        var low = Fixture.charging(); low["CurrentCapacity"] = 15
        _ = e.evaluate(snap(low, at: 0), assessment: nil)
        var off = Fixture.discharging(); off["CurrentCapacity"] = 15
        XCTAssertEqual(e.evaluate(snap(off, at: 2), assessment: nil).map(\.kind), [.unpluggedLow])
    }

    func testCantKeepUpOnTransition() {
        var e = engine()
        let d = Fixture.charging(input: 44000, battery: -900, load: 55000)
        let a = ChargerAssessment(snapshot: snap(d, at: 1000), history: Fixture.history(d, count: 40))
        XCTAssertEqual(a.verdict, .notKeepingUp)
        _ = e.evaluate(snap(d, at: 998), assessment: nil)
        XCTAssertEqual(e.evaluate(snap(d, at: 1000), assessment: a).map(\.kind), [.cantKeepUp])
        XCTAssertTrue(e.evaluate(snap(d, at: 1002), assessment: a).isEmpty, "only on the transition")
    }
}
