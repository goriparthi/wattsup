import XCTest
@testable import WattsupCore

final class HealthTrendTests: XCTestCase {
    func points(days: Int, start: Double = 0.95, perDay: Double = -0.0002, cyclesPerDay: Double = 1) -> [HealthPoint] {
        (0...days).map { d in
            HealthPoint(date: Date(timeIntervalSince1970: Double(d) * 86400), health: start + perDay * Double(d),
                        cycles: 200 + Int(Double(d) * cyclesPerDay), nominalCapacity: nil)
        }
    }

    func testCollectsUntilTwoWeeks() {
        XCTAssertTrue(HealthTrend(points: points(days: 10)).isCollecting)
        XCTAssertFalse(HealthTrend(points: points(days: 14)).isCollecting)
    }

    func testProjectsToServiceLevel() throws {
        let t = HealthTrend(points: points(days: 60))
        // 0.0002 per day is about 0.61 points a month
        XCTAssertEqual(try XCTUnwrap(t.perMonth), 0.0002 * 30.44, accuracy: 1e-6)
        // From 0.938 down to 0.80 at 0.0002 a day is 690 days, about 22.7 months
        XCTAssertEqual(try XCTUnwrap(t.monthsToService), (0.95 - 0.012 - 0.80) / 0.0002 / 30.44, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(t.perHundredCycles), 0.02, accuracy: 1e-6)
    }

    func testFlatOrImprovingHealthHasNoProjection() {
        XCTAssertNil(HealthTrend(points: points(days: 30, perDay: 0)).monthsToService)
    }

    func testRecordsOncePerDayOrOnNewCycle() {
        let a = HealthPoint(date: Date(timeIntervalSince1970: 1000), health: 0.9, cycles: 245, nominalCapacity: nil)
        var b = a; b.date = Date(timeIntervalSince1970: 2000)
        XCTAssertFalse(HealthTrend.shouldRecord(b, after: a))
        b.cycles = 246
        XCTAssertTrue(HealthTrend.shouldRecord(b, after: a))
        var c = a; c.date = Date(timeIntervalSince1970: 90000)
        XCTAssertTrue(HealthTrend.shouldRecord(c, after: a))
    }
}
