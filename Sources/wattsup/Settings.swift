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
        static let metrics = "menuBarMetrics", order = "menuBarOrder", icon = "menuBarIcon", colors = "menuBarColors"
        static let layout = "menuBarLayout", autoUpdate = "checksForUpdates", outlined = "menuBarOutlined"
    }
    private let defaults: UserDefaults

    /// Every reading in the user's order; the checkbox state lives in `shown`.
    var order: [MenuBarMetric] {
        didSet { defaults.set(MenuBarMetric.encode(order), forKey: Key.order) }
    }
    var shown: Set<MenuBarMetric> {
        didSet { defaults.set(MenuBarMetric.encode(metrics), forKey: Key.metrics) }
    }

    /// The shown readings, left to right in the menu bar or top row first when stacked.
    var metrics: [MenuBarMetric] {
        get { order.filter(shown.contains) }
        set {
            shown = Set(newValue)
            order = MenuBarMetric.completeOrder(newValue + order.filter { !newValue.contains($0) })
        }
    }
    var icon: MenuBarIcon { didSet { defaults.set(icon.rawValue, forKey: Key.icon) } }
    var usesColors: Bool { didSet { defaults.set(usesColors, forKey: Key.colors) } }
    var outlined: Bool { didSet { defaults.set(outlined, forKey: Key.outlined) } }
    var layout: MenuBarLayout { didSet { defaults.set(layout.rawValue, forKey: Key.layout) } }
    var checksForUpdates: Bool { didSet { defaults.set(checksForUpdates, forKey: Key.autoUpdate) } }

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?

    /// Injectable so tests never touch the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Key.metrics).map(MenuBarMetric.decode) ?? MenuBarMetric.defaults
        shown = Set(saved)
        // Builds before full ordering only saved the shown list; those lead, the rest follow
        order = MenuBarMetric.completeOrder(defaults.string(forKey: Key.order).map(MenuBarMetric.decode) ?? saved)
        icon = defaults.string(forKey: Key.icon).flatMap(MenuBarIcon.init) ?? .power
        usesColors = defaults.object(forKey: Key.colors) as? Bool ?? true
        outlined = defaults.object(forKey: Key.outlined) as? Bool ?? true
        layout = defaults.string(forKey: Key.layout).flatMap(MenuBarLayout.init) ?? .line
        checksForUpdates = defaults.object(forKey: Key.autoUpdate) as? Bool ?? true
    }

    /// Showing or hiding a reading never moves it; its place in the order is kept.
    func toggle(_ metric: MenuBarMetric) {
        if shown.contains(metric) { shown.remove(metric) } else { shown.insert(metric) }
    }

    /// Moves a reading one place earlier or later in the full order.
    func shift(_ metric: MenuBarMetric, by offset: Int) {
        guard let i = order.firstIndex(of: metric), order.indices.contains(i + offset) else { return }
        order.swapAt(i, i + offset)
    }

    func resetMenuBar() {
        order = MenuBarMetric.defaultOrder
        shown = Set(MenuBarMetric.defaults)
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
            log.error("Login item change failed: \(error.localizedDescription)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}
