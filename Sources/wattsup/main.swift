// Entry point: a menu bar accessory app, plus a few flags for scripts and verification.
import AppKit
import WattsupCore

let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

switch CommandLine.arguments.dropFirst().first {
case "--version":
    print("wattsup \(version)")
case "--snapshot":
    exit(Report.printSnapshot())
case "--render-menubar":
    let dir = CommandLine.arguments.dropFirst(2).first ?? "dist/menubar"
    exit(MainActor.assumeIsolated { MenuBarRender.run(directory: dir) })
case "--diagnostics":
    Diagnostics.printReport()
case "--help", "-h":
    print("""
    wattsup \(version)
      (no arguments)  run in the menu bar
      --dashboard     run and open the dashboard
      --settings      run and open settings
      --snapshot      print one reading and exit
      --diagnostics   print the log folder, recent log lines and saved crash reports
      --version       print the version
    """)
case .some(let arg) where !["--dashboard", "--popover", "--settings"].contains(arg):
    FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
    exit(2)
default:
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
