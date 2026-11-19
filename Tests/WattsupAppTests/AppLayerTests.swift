import AppKit
import XCTest
@testable import wattsup
@testable import WattsupCore

@MainActor
final class AppLayerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "wattsup-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func snapshot(_ d: [String: Any] = AppFixture.charging) -> PowerSnapshot {
        PowerSnapshot(registry: d, date: Date(timeIntervalSinceReferenceDate: 0))!
    }

    func testDefaultsShowFourReadingsAndOrderHoldsEveryReading() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.metrics, MenuBarMetric.defaults)
        XCTAssertEqual(Set(settings.order), Set(MenuBarMetric.allCases))
    }

    func testShiftAndToggleKeepPositions() {
        let settings = AppSettings(defaults: defaults)
        settings.shift(.percent, by: -1)
        XCTAssertEqual(settings.metrics, [.wallWatts, .chargerLoad, .percent, .systemWatts])
        settings.toggle(.chargerLoad)
        XCTAssertEqual(settings.metrics, [.wallWatts, .percent, .systemWatts])
        settings.toggle(.chargerLoad)
        XCTAssertEqual(settings.metrics, [.wallWatts, .chargerLoad, .percent, .systemWatts], "comes back in its old place")
        // Persisted and reloaded
        XCTAssertEqual(AppSettings(defaults: defaults).metrics, settings.metrics)
    }

    func testOldSavedListMigratesToFullOrder() {
        defaults.set("amps,watts", forKey: "menuBarMetrics")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.metrics, [.amps, .watts])
        XCTAssertEqual(Array(settings.order.prefix(2)), [.amps, .watts])
        XCTAssertEqual(settings.order.count, MenuBarMetric.allCases.count)
    }

    func testRendererSegmentsCoverIconAndEachReading() {
        let settings = AppSettings(defaults: defaults)
        let s = snapshot()
        let readings = settings.metrics.filter { $0.text(for: s) != nil }
        let r = StatusItemRenderer.render(readings, snapshot: s, settings: settings)
        XCTAssertEqual(r.segments.count, readings.count + 1, "one hover region per reading plus the icon")
        XCTAssertNil(r.segments.first?.metric)
        XCTAssertEqual(r.image.size.height, StatusItemRenderer.height)
        // Regions run left to right without overlapping and stay inside the image
        let xs = r.segments.dropFirst().map(\.rect)
        for (a, b) in zip(xs, xs.dropFirst()) { XCTAssertLessThanOrEqual(a.maxX, b.minX + 0.5) }
        XCTAssertLessThanOrEqual(xs.last!.maxX, r.image.size.width + 0.5)
    }

    func testStackedLayoutIsNarrowerThanOneLine() {
        let settings = AppSettings(defaults: defaults)
        settings.metrics = [.watts, .volts, .amps, .percent, .systemWatts, .temperature]
        let s = snapshot()
        let line = StatusItemRenderer.render(settings.metrics, snapshot: s, settings: settings).image.size.width
        settings.layout = .stacked
        let stacked = StatusItemRenderer.render(settings.metrics, snapshot: s, settings: settings)
        XCTAssertLessThan(stacked.image.size.width, line)
        XCTAssertEqual(Set(stacked.segments.compactMap(\.metric)), Set(settings.metrics))
    }

    func testLowPowerTintsOnlyWhenColored() {
        XCTAssertNotNil(StatusItemRenderer.energyTint(.low))
        XCTAssertNotNil(StatusItemRenderer.energyTint(.high))
        XCTAssertNil(StatusItemRenderer.energyTint(.automatic))
        let settings = AppSettings(defaults: defaults)
        settings.usesColors = false
        let image = StatusItemRenderer.image(settings.metrics, snapshot: snapshot(), settings: settings)
        XCTAssertTrue(image.isTemplate, "plain mode stays a template so it adapts to any menu bar")
    }
}

/// A charging reading in registry form, kept separate from the core fixtures on purpose.
enum AppFixture {
    static let charging: [String: Any] = [
        "CurrentCapacity": 89, "MaxCapacity": 100, "ExternalConnected": true, "IsCharging": true,
        "FullyCharged": false, "AvgTimeToFull": 47, "Voltage": 12789, "InstantAmperage": 2124,
        "Temperature": 3057, "DesignCapacity": 8579, "AppleRawMaxCapacity": 8054,
        "NominalChargeCapacity": 8298, "AppleRawCurrentCapacity": 7159,
        "AdapterDetails": ["Watts": 45, "AdapterVoltage": 20000, "Current": 2250, "UsbHvcHvcIndex": 0,
                           "UsbHvcMenu": [["Index": 0, "MaxCurrent": 2250, "MaxVoltage": 20000]]] as [String: Any],
        "PowerTelemetryData": ["SystemPowerIn": 43020, "SystemLoad": 15857, "SystemVoltageIn": 19630,
                               "SystemCurrentIn": 2192, "AdapterEfficiencyLoss": 1183] as [String: Any],
    ]
}

@MainActor
final class AppPresenceTests: XCTestCase {
    func testRegularWhileAWindowIsOpenAccessoryAfter() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let presence = AppPresence()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        presence.track(window)
        XCTAssertEqual(app.activationPolicy(), .regular, "shows in Cmd+Tab and the Dock while open")
        XCTAssertNotNil(app.mainMenu?.item(withTitle: "Window") ?? app.mainMenu?.items.last)
        window.close()
        // The policy switches back on the next turn of the run loop
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(app.activationPolicy(), .accessory, "back to menu bar only once closed")
    }
}
