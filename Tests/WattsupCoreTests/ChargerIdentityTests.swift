import XCTest
@testable import WattsupCore

final class ChargerIdentityTests: XCTestCase {
    func apple(serial: String?) -> [String: Any] {
        var d = Fixture.charging()
        var a = Fixture.adapter45
        a["Name"] = "96W USB-C Power Adapter"
        a["Manufacturer"] = "Apple Inc."
        if let serial { a["SerialString"] = serial }
        d["AdapterDetails"] = a
        return d
    }

    func testSerialSeparatesIdenticalAppleChargers() throws {
        let one = try XCTUnwrap(Fixture.snapshot(apple(serial: "C4H123")).adapter)
        let two = try XCTUnwrap(Fixture.snapshot(apple(serial: "C4H999")).adapter)
        XCTAssertNotEqual(one.fingerprint, two.fingerprint)
        XCTAssertEqual(one.legacyFingerprint, two.legacyFingerprint, "without serials they look the same")
        XCTAssertEqual(one.fingerprint, "serial|C4H123")
    }

    func testOldEntryIsAdoptedWhenItsSerialFirstAppears() throws {
        var log = ChargerLog()
        log.record(Fixture.snapshot(apple(serial: nil), at: 0), verdict: nil)
        let old = try XCTUnwrap(log.records.first?.fingerprint)
        log.rename(old, to: "Desk Apple")
        log.record(Fixture.snapshot(apple(serial: "C4H123"), at: 10), verdict: nil)
        XCTAssertEqual(log.records.count, 1, "the same charger, now known by its serial")
        XCTAssertEqual(log.records.first?.fingerprint, "serial|C4H123")
        XCTAssertEqual(log.records.first?.displayName, "Desk Apple", "its name comes along")
    }

    func testThirdPartyChargersKeepTheNegotiatedIdentity() throws {
        let a = try XCTUnwrap(Fixture.snapshot(Fixture.charging()).adapter)
        XCTAssertNil(a.serial)
        XCTAssertEqual(a.fingerprint, a.legacyFingerprint)
    }
}

final class ChargerMergeTests: XCTestCase {
    func record(_ id: String, watts: Double, name: String? = nil, quality: ChargerQuality.Grade? = nil,
                seen: Double = 0, seconds: Double = 60) -> ChargerRecord {
        var r = ChargerRecord(fingerprint: id, title: "\(Int(watts)) W USB-C charger", ratedWatts: nil, ceilingWatts: watts,
                              profiles: [], firstSeen: Date(timeIntervalSince1970: seen), lastSeen: Date(timeIntervalSince1970: seen),
                              secondsConnected: seconds, peakInputWatts: watts * 0.9, peakDemandWatts: watts, lastVerdict: nil)
        r.nickname = name
        r.qualityGrade = quality?.rawValue
        return r
    }

    func testMergeMakesOneBrickRankedOnItsBestCable() throws {
        var log = ChargerLog(records: [record("cable3A", watts: 60, quality: .good, seen: 1),
                                       record("cable5A", watts: 100, name: "Belkin", quality: .excellent, seen: 2),
                                       record("other", watts: 70, seen: 3)])
        log.merge("cable3A", into: "cable5A")
        let bricks = Brick.group(log.records)
        XCTAssertEqual(bricks.count, 2)
        let belkin = try XCTUnwrap(bricks.first { $0.id == "cable5A" })
        XCTAssertEqual(belkin.members.count, 2)
        XCTAssertEqual(belkin.displayName, "Belkin")
        XCTAssertEqual(belkin.combined.ceilingWatts, 100)
        XCTAssertEqual(belkin.combined.quality, .excellent)
        XCTAssertEqual(belkin.combined.secondsConnected, 120, "time on either cable counts")
        XCTAssertEqual(log.name(for: "cable3A"), "Belkin", "the connected cable shows the brick's name")
        XCTAssertEqual(ChargerRanking.rankedBricks(log.records, by: .power).first?.brick.id, "cable5A")
    }

    func testNameCarriesOverAndSeparateUndoes() {
        var log = ChargerLog(records: [record("a", watts: 60, name: "Travel"), record("b", watts: 100)])
        log.merge("a", into: "b")
        XCTAssertEqual(log.name(for: "b"), "Travel", "the target had no name, so the source's moves over")
        log.separate("a")
        XCTAssertEqual(Brick.group(log.records).count, 2)
    }

    func testSeparatingTheRootPromotesAnotherMember() {
        var log = ChargerLog(records: [record("root", watts: 100, name: "Brick"), record("x", watts: 60), record("y", watts: 45)])
        log.merge("x", into: "root")
        log.merge("y", into: "root")
        log.separate("root")
        let bricks = Brick.group(log.records)
        XCTAssertEqual(bricks.count, 2)
        XCTAssertTrue(bricks.contains { $0.members.count == 2 && $0.displayName == "Brick" }, "the rest stay together, keeping the name")
    }

    func testForgetBrickRemovesEveryCable() {
        var log = ChargerLog(records: [record("a", watts: 60), record("b", watts: 100), record("c", watts: 45)])
        log.merge("a", into: "b")
        log.forgetBrick("b")
        XCTAssertEqual(log.records.map(\.fingerprint), ["c"])
    }
}
