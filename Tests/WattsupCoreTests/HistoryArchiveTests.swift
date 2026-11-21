import XCTest
@testable import WattsupCore

final class HistoryArchiveTests: XCTestCase {
    func sample(at t: Double, input: Int) -> PowerSample {
        var s = PowerSample(Fixture.snapshot(Fixture.charging(input: input), at: 0))
        s.date = Date(timeIntervalSince1970: t)
        return s
    }

    func testAggregatesOneMinute() throws {
        var agg = MinuteAggregator()
        XCTAssertNil(agg.add(sample(at: 120, input: 40000)))
        XCTAssertNil(agg.add(sample(at: 150, input: 20000)))
        let minute = try XCTUnwrap(agg.add(sample(at: 180, input: 10000)), "a new minute closes the old one")
        XCTAssertEqual(minute.date, Date(timeIntervalSince1970: 120))
        XCTAssertEqual(minute.inputWatts, 30, accuracy: 0.001)
        XCTAssertEqual(minute.seconds, 32, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(agg.pending()).inputWatts, 10, accuracy: 0.001)
    }

    func testRoundTripsAndSkipsTornLines() throws {
        let a = try XCTUnwrap(HistoryArchive.encode(sample(at: 60, input: 30000)))
        var data = a
        data.append(Data("{\"torn".utf8))
        data.append(0x0A)
        data.append(try XCTUnwrap(HistoryArchive.encode(sample(at: 120, input: 20000))))
        let back = HistoryArchive.decode(data)
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].inputWatts, 30, accuracy: 0.001)
    }

    func testDayFilesAndExpiry() {
        let now = Date(timeIntervalSince1970: 86400 * 40)
        XCTAssertEqual(HistoryArchive.fileName(for: now), "1970-02-10.jsonl")
        let names = ["1970-01-01.jsonl", "1970-02-09.jsonl", "notes.txt"]
        XCTAssertEqual(HistoryArchive.expired(names, now: now, days: 30), ["1970-01-01.jsonl"])
    }

    func testRebalancesMinutesWhereMacUseExceededTheCharger() throws {
        // A 0.0.6 minute: 87 W in, battery took 70.7 W, yet SystemLoad put the Mac at 82.5 W
        var m = sample(at: 60, input: 86957)
        m.batteryWatts = 70.7; m.systemWatts = 82.5; m.demandWatts = 82.5 + 92
        var data = try XCTUnwrap(HistoryArchive.encode(m))
        data.append(0x0A)
        let fixed = try XCTUnwrap(HistoryArchive.decode(data).first)
        XCTAssertEqual(fixed.systemWatts, 86.957 - 70.7, accuracy: 0.001)
        XCTAssertEqual(fixed.demandWatts, 86.957 - 70.7 + 92, accuracy: 0.001)
        XCTAssertEqual(fixed.balanced(), fixed, "already balanced minutes are unchanged")
    }

    func testLeavesBatteryMinutesAlone() {
        var m = sample(at: 60, input: 0)
        m.isExternalPower = false; m.systemWatts = 9; m.batteryWatts = -9; m.demandWatts = 9
        XCTAssertEqual(m.balanced(), m)
    }
}

final class ChartGapTests: XCTestCase {
    func testBreaksOnlyAcrossLongGaps() {
        let t = [0, 60, 120, 4000, 4060, 4120, 20000].map { Date(timeIntervalSince1970: Double($0)) }
        XCTAssertEqual(ChartGaps.segments(t), [0, 0, 0, 1, 1, 1, 2])
        XCTAssertEqual(ChartGaps.segments([]), [])
    }
}
