import XCTest
@testable import WattsupCore

final class ChargerRankingTests: XCTestCase {
    func charger(_ id: String, watts: Double?, efficiency: Double?, grade: ChargerQuality.Grade?, seen: Double) -> ChargerRecord {
        var r = ChargerRecord(fingerprint: id, title: "\(Int(watts ?? 0)) W USB-C charger", ratedWatts: nil,
                              ceilingWatts: watts, profiles: [], firstSeen: Date(timeIntervalSince1970: 0),
                              lastSeen: Date(timeIntervalSince1970: seen), secondsConnected: 600,
                              peakInputWatts: 0, peakDemandWatts: 0, lastVerdict: nil)
        if let efficiency { r.efficiencyTotal = efficiency; r.efficiencyCount = 1 }
        r.qualityGrade = grade?.rawValue
        return r
    }

    func testOverallBlendsPowerEfficiencyAndQuality() throws {
        let big = charger("a", watts: 100, efficiency: 0.98, grade: .excellent, seen: 1)
        let small = charger("b", watts: 45, efficiency: 0.97, grade: .excellent, seen: 3)
        let poor = charger("c", watts: 70, efficiency: 0.86, grade: .poor, seen: 2)
        let ranked = ChargerRanking.ranked([small, poor, big], by: .overall)
        XCTAssertEqual(ranked.map(\.id), ["a", "b", "c"])
        // 100 W, 98%, excellent: 0.4*1 + 0.3*0.9 + 0.3*1 = 0.97
        XCTAssertEqual(try XCTUnwrap(ranked.first?.score), 97, accuracy: 0.01)
    }

    func testUnmeasuredFactorsAreLeftOutNotZeroed() throws {
        let fresh = charger("x", watts: 60, efficiency: nil, grade: nil, seen: 1)
        let e = try XCTUnwrap(ChargerRanking.entries([fresh]).first)
        XCTAssertEqual(e.measured, ["power"])
        XCTAssertEqual(try XCTUnwrap(e.score), 100, accuracy: 0.01, "only power known, and it is the strongest")
        let nothing = charger("y", watts: nil, efficiency: nil, grade: nil, seen: 1)
        XCTAssertNil(ChargerRanking.entries([nothing]).first?.score)
    }

    func testOtherOrdersAndTieBreak() {
        let a = charger("a", watts: 60, efficiency: 0.90, grade: .good, seen: 1)
        let b = charger("b", watts: 60, efficiency: 0.95, grade: .fair, seen: 2)
        XCTAssertEqual(ChargerRanking.ranked([a, b], by: .power).map(\.id), ["b", "a"], "equal power falls back to recent")
        XCTAssertEqual(ChargerRanking.ranked([a, b], by: .efficiency).map(\.id), ["b", "a"])
        XCTAssertEqual(ChargerRanking.ranked([a, b], by: .quality).map(\.id), ["a", "b"])
        XCTAssertEqual(ChargerRanking.ranked([a, b], by: .recent).map(\.id), ["b", "a"])
    }

    func testRenameTrimsCapsAndClears() throws {
        var log = ChargerLog()
        log.record(Fixture.snapshot(Fixture.charging(), at: 0), verdict: nil)
        let fp = try XCTUnwrap(log.records.first?.fingerprint)
        log.rename(fp, to: "  Hotel Anker  ")
        XCTAssertEqual(log.records.first?.displayName, "Hotel Anker")
        log.rename(fp, to: String(repeating: "x", count: 80))
        XCTAssertEqual(log.records.first?.nickname?.count, 40)
        log.rename(fp, to: "   ")
        XCTAssertEqual(log.records.first?.displayName, "45 W USB-C charger", "empty name returns to the detected title")
    }
}
