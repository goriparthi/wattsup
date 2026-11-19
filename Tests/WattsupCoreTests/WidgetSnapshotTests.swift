import XCTest
@testable import WattsupCore

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTripAndPath() throws {
        let w = WidgetSnapshot(Fixture.snapshot(Fixture.charging()), verdict: "Charger has headroom")
        let back = try XCTUnwrap(WidgetSnapshot.decode(try XCTUnwrap(w.encoded())))
        XCTAssertEqual(back, w)
        XCTAssertTrue(WidgetSnapshot.containerURL(home: URL(fileURLWithPath: "/Users/x")).path
            .hasSuffix("Containers/com.goriparthi.wattsup.widget/Data/Library/Application Support/Wattsup/widget.json"))
    }

    func testOnlyMeaningfulChangesArePushed() {
        let a = WidgetSnapshot(Fixture.snapshot(Fixture.charging(), at: 0), verdict: nil)
        var b = a
        b.macWatts += 0.5
        XCTAssertFalse(b.differsMeaningfully(from: a))
        b.percent += 1
        XCTAssertTrue(b.differsMeaningfully(from: a))
        XCTAssertTrue(a.differsMeaningfully(from: nil))
    }
}
