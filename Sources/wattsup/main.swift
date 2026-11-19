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
case "--thermals":
    // Prints what the SMC exposes on this Mac, for checking sensor coverage per model
    guard let smc = SMC() else { print("AppleSMC unavailable"); exit(1) }
    let keys = smc.allKeys()
    let chips = keys.filter(Thermals.isChipSensor)
    var temps: [String: Double] = [:]
    for k in chips { temps[k] = smc.read(k) }
    let t = Thermals.summarize(fans: smc.fans(), temperatures: temps.compactMapValues { $0 })
    print("SMC keys: \(keys.count), chip sensors: \(chips.count)")
    for f in t.fans { print("\(f.name(of: t.fans.count)): \(Int(f.rpm)) rpm (range \(Int(f.minRPM ?? 0)) to \(Int(f.maxRPM ?? 0)))") }
    print(String(format: "CPU %.1f C (hottest %.1f), GPU %.1f C", t.cpuC ?? -1, t.cpuHottestC ?? -1, t.gpuC ?? -1))
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
