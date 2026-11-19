import XCTest
@testable import WattsupCore

final class EnergyImpactTests: XCTestCase {
    let sample = """
    Processes: 600 total
    PID    COMMAND          POWER
    1      launchd          900.0
    PID    COMMAND          POWER
    23234  WindowServer     31.4
    2817   Google Chrome He 24.1
    2825   Google Chrome He 14.9
    6462   zoom.us          25.8
    999    idle thing       0.0
    """

    func testKeepsOnlyTheLastSample() {
        let p = EnergyImpact.parse(top: sample)
        XCTAssertEqual(p.count, 5)
        XCTAssertEqual(p.first?.command, "WindowServer")
        XCTAssertEqual(p[1].command, "Google Chrome He", "commands with spaces stay whole")
        XCTAssertFalse(p.contains { $0.pid == 1 }, "the cumulative first sample is ignored")
    }

    func testGroupsHelpersUnderTheirApp() {
        let paths: [Int32: String] = [
            2817: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
            2825: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            6462: "/Applications/zoom.us.app/Contents/MacOS/zoom.us",
        ]
        let apps = EnergyImpact.group(EnergyImpact.parse(top: sample)) { pid in
            paths[pid].flatMap(EnergyImpact.appBundle(inPath:))
        }
        XCTAssertEqual(apps.first?.name, "Google Chrome")
        XCTAssertEqual(apps.first?.impact ?? 0, 39, accuracy: 0.001)
        XCTAssertEqual(apps.first?.processes, 2)
        XCTAssertEqual(apps.map(\.name), ["Google Chrome", "WindowServer", "zoom.us"], "zero impact dropped")
    }

    func testAppBundleFromPath() {
        XCTAssertEqual(EnergyImpact.appBundle(inPath: "/Applications/Foo Bar.app/Contents/MacOS/foo")?.name, "Foo Bar")
        XCTAssertNil(EnergyImpact.appBundle(inPath: "/usr/libexec/coreaudiod"))
    }
}
