import XCTest
@testable import WattsupCore

final class LogFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wattsup-log-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testLineIsUTCAndSingleLine() {
        let line = LogFile.line(.error, "first\nsecond", date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(line, "1970-01-01T00:00:00.000Z ERROR first\\nsecond\n")
    }

    func testWritesAndTails() {
        let log = LogFile(directory: dir)
        for i in 1...5 { log.write(.info, "entry \(i)") }
        let tail = log.tail(2)
        XCTAssertEqual(tail.count, 2)
        XCTAssertTrue(tail[1].hasSuffix("INFO entry 5"), tail[1])
    }

    func testRotatesAndKeepsLimit() throws {
        let log = LogFile(directory: dir, maxBytes: 200, keep: 2)
        for i in 1...40 { log.write(.info, "entry number \(i) with some padding") }
        log.flush()
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: log.url.path))
        XCTAssertTrue(fm.fileExists(atPath: log.url.path + ".1"))
        XCTAssertTrue(fm.fileExists(atPath: log.url.path + ".2"))
        XCTAssertFalse(fm.fileExists(atPath: log.url.path + ".3"), "only `keep` rotated files survive")
        let size = try XCTUnwrap(fm.attributesOfItem(atPath: log.url.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, 200)
        XCTAssertTrue(log.tail(1).first?.hasSuffix("entry number 40 with some padding") ?? false)
    }
}
