import AppKit
import SwiftUI
import WattsupCore

/// Owns the status item, its popover and the dashboard window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = PowerMonitor()
    private let settings = AppSettings()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboard: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            monitor: monitor, settings: settings,
            openDashboard: { [weak self] in self?.showDashboard() }))

        monitor.onUpdate = { [weak self] in self?.updateStatusItem() }
        monitor.start()
        observeSettings()

        if CommandLine.arguments.contains("--dashboard") { showDashboard() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.flush()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.metrics
            _ = settings.showsIcon
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItem()
                self?.observeSettings()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard let s = monitor.snapshot else {
            button.image = NSImage(systemSymbolName: "bolt.slash", accessibilityDescription: "Wattsup")
            button.attributedTitle = NSAttributedString()
            return
        }
        let text = MenuBarMetric.line(settings.metrics, for: s)
        let showIcon = settings.showsIcon || text.isEmpty
        let image = NSImage(systemSymbolName: s.symbolName, accessibilityDescription: s.state.title)
        image?.isTemplate = true
        button.image = showIcon ? image : nil
        button.attributedTitle = NSAttributedString(
            string: text.isEmpty ? "" : (showIcon ? " " : "") + text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium),
                .baselineOffset: 0.5,
            ])
        button.setAccessibilityLabel("Wattsup, \(s.statusLine), \(text)")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
            window.contentView = NSHostingView(rootView: DashboardView(monitor: monitor, settings: settings))
            window.setFrameAutosaveName("WattsupDashboard")
            window.center()
            dashboard = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }
}
