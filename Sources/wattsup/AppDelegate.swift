import AppKit
import SwiftUI
import WattsupCore

/// Owns the status item, its popover and the dashboard window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PowerMonitor()
    private let settings = AppSettings()
    private lazy var updates = UpdateController(settings: settings)
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private static let welcomedKey = "hasSeenWelcome"
    private let visibility = MenuBarVisibility()
    private let presence = AppPresence()
    private lazy var alerts = AlertCenter(settings: settings)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboard: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.launched(version: Updates.bundleVersion)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(rootView: PopoverView(
            monitor: monitor, settings: settings, actions: PopoverActions(
                openDashboard: { [weak self] in self?.showDashboard() },
                openSettings: { [weak self] in self?.showSettings() },
                openWelcome: { [weak self] in self?.showWelcome() },
                checkForUpdates: { [weak self] in
                    guard let self else { return }
                    Task { await self.updates.check(interactive: true) }
                })))
        // The popover follows SwiftUI's size; a stale size makes it grow upward off screen
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            self.updateStatusItem()
            self.alerts.evaluate(self.monitor.snapshot, self.monitor.assessment)
            self.alerts.receipt(self.monitor.latestReceipt,
                                chargerName: self.monitor.chargers.name(for: self.monitor.latestReceipt?.charger))
        }
        alerts.start()
        monitor.start()
        observeSettings()
        updates.start()
        visibility.openDashboard = { [weak self] in self?.showDashboard() }
        presence.openSettings = { [weak self] in self?.showSettings() }
        visibility.watch(statusItem)

        if CommandLine.arguments.contains("--dashboard") { showDashboard() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--welcome") || !UserDefaults.standard.bool(forKey: Self.welcomedKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showWelcome() }
        }
        // Opens the popover at launch so its layout can be checked without a click
        if CommandLine.arguments.contains("--popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.togglePopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.flush()
        Diagnostics.quitCleanly()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = (settings.metrics, settings.icon, settings.usesColors, settings.layout, settings.outlined)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItem()
                self?.observeSettings()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        StatusItemRenderer.apply(to: button, snapshot: monitor.snapshot, settings: settings)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.refresh()
            if let view = popover.contentViewController?.view {
                view.layoutSubtreeIfNeeded()
                popover.contentSize = view.fittingSize
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showWelcome() {
        popover.performClose(nil)
        if welcomeWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Welcome"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WelcomeView(settings: settings) { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.welcomedKey)
                self?.welcomeWindow?.close()
            })
            window.center()
            welcomeWindow = window
        }
        if let window = welcomeWindow { presence.track(window) }
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Wattsup Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(monitor: monitor, settings: settings, updates: updates))
            window.center()
            settingsWindow = window
        }
        if let window = settingsWindow { presence.track(window) }
    }

    func showDashboard() {
        popover.performClose(nil)
        if dashboard == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Wattsup"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DashboardView(monitor: monitor, settings: settings, visibility: visibility))
            window.setFrameAutosaveName("WattsupDashboard")
            window.center()
            dashboard = window
        }
        if let window = dashboard { presence.track(window) }
    }
}
