import XCTest
@testable import WattsupCore

final class SessionTests: XCTestCase {
    func charging(_ pct: Int, batteryMA: Int = 3000) -> [String: Any] {
        var d = Fixture.charging(input: 43000, battery: batteryMA)
        d["CurrentCapacity"] = pct
        return d
    }

    func testReceiptFromPlugInToUnplug() throws {
        var t = SessionTracker()
        var finished: ChargingSession?
        // 20 minutes at 2 s steps, rising from 60% to 85%
        for i in 0...600 {
            let pct = 60 + i * 25 / 600
            finished = t.update(Fixture.snapshot(charging(pct), at: Double(i) * 2), limited: i < 300) ?? finished
        }
        XCTAssertNil(finished, "still plugged in")
        finished = t.update(Fixture.snapshot(Fixture.discharging(), at: 1202), limited: false)
        let s = try XCTUnwrap(finished)
        XCTAssertEqual(s.startPercent, 60)
        XCTAssertEqual(s.endPercent, 85)
        XCTAssertEqual(s.duration, 1200, accuracy: 0.01)
        // 12.789 V x 3 A for 1200 s is about 12.8 Wh into the battery
        XCTAssertEqual(s.batteryWh, 12.789 * 3 * 1200 / 3600, accuracy: 0.1)
        XCTAssertEqual(s.limitedShare, 0.5, accuracy: 0.01)
        XCTAssertNotNil(s.minutesTo80)
        XCTAssertTrue(s.summary.hasPrefix("60% to 85% in 20 min"), s.summary)
    }

    func testBlipsAreNotReceipts() {
        var t = SessionTracker()
        _ = t.update(Fixture.snapshot(charging(50), at: 0), limited: false)
        _ = t.update(Fixture.snapshot(charging(50), at: 30), limited: false)
        XCTAssertNil(t.update(Fixture.snapshot(Fixture.discharging(), at: 32), limited: false), "under two minutes")
    }
}

final class InsightsTests: XCTestCase {
    func minute(_ i: Int, demand: Double, plugged: Bool = true, percent: Int = 80, temp: Double = 30) -> PowerSample {
        var s = PowerSample(Fixture.snapshot(Fixture.charging(), at: 0))
        s.date = Date(timeIntervalSince1970: Double(i) * 60)
        s.seconds = 60; s.demandWatts = demand; s.isExternalPower = plugged; s.percent = percent; s.temperatureC = temp
        return s
    }

    func brick(_ id: String, watts: Double, name: String) -> Brick {
        var r = ChargerRecord(fingerprint: id, title: "\(Int(watts)) W USB-C charger", ratedWatts: nil, ceilingWatts: watts,
                              profiles: [], firstSeen: Date(), lastSeen: Date(), secondsConnected: 60,
                              peakInputWatts: 0, peakDemandWatts: 0, lastVerdict: nil)
        r.nickname = name
        return Brick.group([r])[0]
    }

    func testPacksTheSmallestThatCoversHeavyUse() throws {
        // Two hours: mostly 20 W, a heavy tail near 60 W
        let samples = (0..<120).map { minute($0, demand: $0 % 20 == 0 ? 62 : 20) }
        let advice = try XCTUnwrap(PackAdvice(samples: samples, bricks: [brick("a", watts: 45, name: "Small"),
                                                                        brick("b", watts: 70, name: "Medium"),
                                                                        brick("c", watts: 100, name: "Big")]))
        XCTAssertEqual(advice.typicalWatts, 20)
        XCTAssertEqual(advice.heavyWatts, 62)
        XCTAssertEqual(advice.keepsUp?.displayName, "Medium")
        XCTAssertEqual(advice.fastest?.displayName, "Big")
        XCTAssertEqual(advice.headline, "Pack Medium")
    }

    func testNeedsAnHourOfChargerTime() {
        XCTAssertNil(PackAdvice(samples: (0..<30).map { minute($0, demand: 20) }, bricks: [brick("a", watts: 45, name: "x")]))
    }

    func testBatteryCareHabits() throws {
        var samples = (0..<1680).map { minute($0, demand: 20, percent: 99, temp: 30) }         // 28 h plugged near full
        samples += (1680..<1800).map { minute($0, demand: 20, plugged: false, percent: 60 - ($0 - 1680) / 2, temp: 41) } // 2 h hot, draining to 1%
        let care = try XCTUnwrap(BatteryCare(samples: samples))
        XCTAssertEqual(care.highChargeHours, 28, accuracy: 0.01)
        XCTAssertEqual(care.hotHours, 2, accuracy: 0.01)
        XCTAssertEqual(care.deepDischarges, 1)
        XCTAssertTrue(care.tips.contains { $0.contains("charge limit") })
        XCTAssertTrue(care.tips.contains { $0.contains("Heat") })
    }

    func testWeeklyAdviceWaitsForADayOfHistory() throws {
        let care = try XCTUnwrap(BatteryCare(samples: (0..<240).map { minute($0, demand: 20, percent: 99) }))
        XCTAssertEqual(care.highChargeHours, 4, accuracy: 0.01, "the plain count still shows")
        XCTAssertFalse(care.tips.contains { $0.contains("hours a week") }, "no weekly projection from 4 hours")
        XCTAssertTrue(care.tips.contains { $0.contains("after a day of history") })
    }
}
