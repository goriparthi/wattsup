import AppKit
import Observation
import WattsupCore

/// Notices when macOS hides the status item: a full menu bar, the notch, or Allow in Menu Bar off.
@MainActor @Observable
final class MenuBarVisibility {
    private(set) var hidden = false
    @ObservationIgnored private weak var item: NSStatusItem?
    @ObservationIgnored private var warned = false
    @ObservationIgnored var openDashboard: () -> Void = {}
    private static let suppressKey = "suppressHiddenMenuBarWarning"

    func watch(_ item: NSStatusItem) {
        self.item = item
        // Give the menu bar time to lay out, then recheck when screens or spaces change
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.check() }
        for name in [NSApplication.didChangeScreenParametersNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            let center = name == NSWorkspace.activeSpaceDidChangeNotification ? NSWorkspace.shared.notificationCenter : .default
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        }
    }

    func check() {
        guard let window = item?.button?.window else { return }
        let visible = Self.isVisible(window)
        let wasHidden = hidden
        hidden = !visible
        guard hidden != wasHidden || !warned else { return }
        log.info("Menu bar readout \(visible ? "visible" : "hidden by macOS") at \(Int(window.frame.minX)),\(Int(window.frame.minY)) width \(Int(window.frame.width))")
        if hidden && !wasHidden && !warned { warn() }
    }

    static func isVisible(_ window: NSWindow) -> Bool {
        // Position only: macOS also reports menu bar items as occluded when switching spaces or
        // in full screen apps, which is not hiding and caused false alerts
        guard let screen = window.screen ?? NSScreen.main else { return false }
        return MenuBarGeometry.isVisible(item: window.frame, screen: screen.frame,
                                         leftOfNotch: screen.auxiliaryTopLeftArea,
                                         rightOfNotch: screen.auxiliaryTopRightArea)
    }

    private func warn() {
        warned = true
        guard !UserDefaults.standard.bool(forKey: Self.suppressKey) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Wattsup is running, but macOS hid its menu bar readout"
        alert.informativeText = "The menu bar is full or the notch covers it. Remove a few items (Command drag them out), "
            + "or check that Wattsup is allowed in Menu Bar settings. The dashboard works either way."
        alert.addButton(withTitle: "Open Menu Bar Settings")
        alert.addButton(withTitle: "Open Dashboard")
        alert.addButton(withTitle: "OK")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show this again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: Self.suppressKey) }
        switch response {
        case .alertFirstButtonReturn: SystemSettings.openMenuBar()
        case .alertSecondButtonReturn: openDashboard()
        default: break
        }
    }
}
