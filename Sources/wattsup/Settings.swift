import Foundation
import Observation
import ServiceManagement
import WattsupCore

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class AppSettings {
    static let metricsKey = "menuBarMetrics"
    static let iconKey = "menuBarShowsIcon"

    var metrics: [MenuBarMetric] {
        didSet { UserDefaults.standard.set(MenuBarMetric.encode(metrics), forKey: Self.metricsKey) }
    }

    var showsIcon: Bool {
        didSet { UserDefaults.standard.set(showsIcon, forKey: Self.iconKey) }
    }

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.metricsKey)
        metrics = stored.map(MenuBarMetric.decode) ?? MenuBarMetric.defaults
        showsIcon = UserDefaults.standard.object(forKey: Self.iconKey) as? Bool ?? true
    }

    /// Keeps the menu bar in enum order so toggling never shuffles the readout.
    func toggle(_ metric: MenuBarMetric) {
        var set = Set(metrics)
        if set.contains(metric) { set.remove(metric) } else { set.insert(metric) }
        metrics = MenuBarMetric.allCases.filter(set.contains)
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}
