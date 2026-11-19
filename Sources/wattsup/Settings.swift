import Foundation
import Observation
import ServiceManagement
import WattsupCore

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case power, battery, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .power: return "Power, bolt and plug"
        case .battery: return "Battery state"
        case .none: return "None"
        }
    }
}

enum MenuBarLayout: String, CaseIterable, Identifiable {
    case line, stacked
    var id: String { rawValue }
    var title: String { self == .line ? "Single line" : "Stacked, two rows" }
}

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let metrics = "menuBarMetrics", icon = "menuBarIcon", colors = "menuBarColors"
        static let layout = "menuBarLayout", autoUpdate = "checksForUpdates", outlined = "menuBarOutlined"
    }
    private let defaults = UserDefaults.standard

    /// In the user's order; the menu bar shows them left to right, or top row first.
    var metrics: [MenuBarMetric] {
        didSet { defaults.set(MenuBarMetric.encode(metrics), forKey: Key.metrics) }
    }
    var icon: MenuBarIcon { didSet { defaults.set(icon.rawValue, forKey: Key.icon) } }
    var usesColors: Bool { didSet { defaults.set(usesColors, forKey: Key.colors) } }
    var outlined: Bool { didSet { defaults.set(outlined, forKey: Key.outlined) } }
    var layout: MenuBarLayout { didSet { defaults.set(layout.rawValue, forKey: Key.layout) } }
    var checksForUpdates: Bool { didSet { defaults.set(checksForUpdates, forKey: Key.autoUpdate) } }

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?

    init() {
        metrics = defaults.string(forKey: Key.metrics).map(MenuBarMetric.decode) ?? MenuBarMetric.defaults
        icon = defaults.string(forKey: Key.icon).flatMap(MenuBarIcon.init) ?? .power
        usesColors = defaults.object(forKey: Key.colors) as? Bool ?? true
        outlined = defaults.object(forKey: Key.outlined) as? Bool ?? true
        layout = defaults.string(forKey: Key.layout).flatMap(MenuBarLayout.init) ?? .line
        checksForUpdates = defaults.object(forKey: Key.autoUpdate) as? Bool ?? true
    }

    /// New readings join at the end, so turning one on never reshuffles the rest.
    func toggle(_ metric: MenuBarMetric) {
        if let i = metrics.firstIndex(of: metric) { metrics.remove(at: i) } else { metrics.append(metric) }
    }

    func move(from source: IndexSet, to destination: Int) {
        metrics.move(fromOffsets: source, toOffset: destination)
    }

    func resetMenuBar() {
        metrics = MenuBarMetric.defaults
        layout = .line
        usesColors = true
        icon = .power
        outlined = true
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
