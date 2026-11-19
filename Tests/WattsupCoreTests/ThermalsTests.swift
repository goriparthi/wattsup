import XCTest
@testable import WattsupCore

final class ThermalsTests: XCTestCase {
    func testFourCCRoundTrip() {
        XCTAssertEqual(SMCValue.fourCC("FNum"), 0x464E_756D)
        XCTAssertEqual(SMCValue.string(SMCValue.fourCC("F0Ac")), "F0Ac")
    }

    func testDecodesTypes() throws {
        // 2150.0 as a little endian float
        let bits = Float(2150).bitPattern
        let flt = [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
        XCTAssertEqual(try XCTUnwrap(SMCValue.decode(type: "flt ", bytes: flt)), 2150, accuracy: 0.001)
        XCTAssertEqual(SMCValue.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCValue.decode(type: "ui16", bytes: [0x01, 0x00]), 256)
        XCTAssertEqual(SMCValue.decode(type: "fpe2", bytes: [0x1F, 0x40]), 2000)
        XCTAssertEqual(try XCTUnwrap(SMCValue.decode(type: "sp78", bytes: [0x2A, 0x80])), 42.5, accuracy: 0.001)
        XCTAssertNil(SMCValue.decode(type: "zzzz", bytes: [1, 2, 3, 4]))
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [1, 2]))
    }

    func testSummaryDropsImplausibleAndSplitsCPUGPU() throws {
        let t = Thermals.summarize(fans: [Fan(index: 0, rpm: 1800, minRPM: 1200, maxRPM: 5800)],
                                   temperatures: ["Tp01": 50, "Te05": 40, "Tp09": 70, "Tg0f": 45, "Tp0X": 0.5, "TB0T": 30])
        XCTAssertEqual(try XCTUnwrap(t.cpuC), 160.0 / 3, accuracy: 0.001)
        XCTAssertEqual(t.cpuHottestC, 70)
        XCTAssertEqual(t.gpuC, 45)
        XCTAssertEqual(t.fanRPM, 1800)
        XCTAssertEqual(try XCTUnwrap(t.fans.first?.fraction), 600.0 / 4600, accuracy: 0.0001)
    }

    func testFanNames() {
        XCTAssertEqual(Fan(index: 1, rpm: 0, minRPM: nil, maxRPM: nil).name(of: 2), "Right fan")
        XCTAssertEqual(Fan(index: 0, rpm: 0, minRPM: nil, maxRPM: nil).name(of: 1), "Fan")
    }
}
