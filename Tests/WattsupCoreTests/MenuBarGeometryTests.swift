import XCTest
@testable import WattsupCore

final class MenuBarGeometryTests: XCTestCase {
    // A 16 inch MacBook Pro: 1728 wide, notch roughly between x 776 and 952, menu bar at the top
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let left = CGRect(x: 0, y: 1084, width: 776, height: 33)
    let right = CGRect(x: 952, y: 1084, width: 776, height: 33)

    func testRightOfNotchIsVisible() {
        XCTAssertTrue(MenuBarGeometry.isVisible(item: CGRect(x: 1313, y: 1084, width: 213, height: 33),
                                                screen: screen, leftOfNotch: left, rightOfNotch: right))
    }

    func testUnderTheNotchIsHidden() {
        XCTAssertFalse(MenuBarGeometry.isVisible(item: CGRect(x: 800, y: 1084, width: 120, height: 33),
                                                 screen: screen, leftOfNotch: left, rightOfNotch: right))
        XCTAssertFalse(MenuBarGeometry.isVisible(item: CGRect(x: 700, y: 1084, width: 120, height: 33),
                                                 screen: screen, leftOfNotch: left, rightOfNotch: right),
                       "straddling the notch edge")
    }

    func testOffScreenOrCollapsedIsHidden() {
        XCTAssertFalse(MenuBarGeometry.isVisible(item: CGRect(x: -300, y: 1084, width: 100, height: 33),
                                                 screen: screen, leftOfNotch: left, rightOfNotch: right))
        XCTAssertFalse(MenuBarGeometry.isVisible(item: CGRect(x: 1300, y: 1084, width: 0, height: 33),
                                                 screen: screen, leftOfNotch: nil, rightOfNotch: nil))
    }

    func testNoNotchOnlyNeedsToBeOnScreen() {
        XCTAssertTrue(MenuBarGeometry.isVisible(item: CGRect(x: 800, y: 1084, width: 120, height: 33),
                                                screen: screen, leftOfNotch: nil, rightOfNotch: nil))
    }
}
