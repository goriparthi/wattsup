import AppKit

/// Wattsup lives in the menu bar, but while one of its windows is open it behaves like a normal
/// app: it shows in Cmd+Tab and the Dock and has a menu bar, then steps back once they close.
@MainActor
final class AppPresence: NSObject {
    private var windows: [NSWindow] = []
    var openSettings: () -> Void = {}

    func track(_ window: NSWindow) {
        if !windows.contains(window) {
            windows.append(window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.mainMenu = makeMainMenu()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func windowWillClose(_ note: Notification) {
        // Wait a beat: the closing window still counts as visible during this notification
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.windows.contains(where: \.isVisible) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu(title: "Wattsup")
        app.addItem(withTitle: "About Wattsup", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Wattsup", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Wattsup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window
        return main
    }

    @objc private func showSettings() { openSettings() }
}
