import AppKit
import SwiftUI
import WattsupCore

/// `wattsup --render-menubar <dir>`: draws the readout in each layout from a live reading,
/// on light and dark bars, so the status item can be checked without the real menu bar.
@MainActor
enum MenuBarRender {
    static func run(directory: String) -> Int32 {
        guard case .properties(let props) = SmartBattery.read(), var s = PowerSnapshot(registry: props) else {
            FileHandle.standardError.write(Data("no battery reading to render\n".utf8))
            return 1
        }
        let settings = AppSettings()
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let cases: [(String, [MenuBarMetric], MenuBarLayout, MenuBarIcon, Bool)] = [
            ("line", MenuBarMetric.defaults, .line, .power, true),
            ("line-battery-icon", [.watts, .volts, .amps], .line, .battery, true),
            ("stacked", [.watts, .volts, .amps, .percent, .systemWatts, .temperature], .stacked, .power, true),
            ("plain", [.watts, .percent], .line, .power, false),
            ("lowpower", MenuBarMetric.defaults, .line, .power, true),
            ("lowpower-battery-icon", MenuBarMetric.defaults, .line, .battery, true),
        ]
        for (name, metrics, layout, icon, colors) in cases {
            settings.metrics = metrics
            settings.layout = layout
            settings.icon = icon
            settings.usesColors = colors
            // The live reading, with Low Power switched on for the two cases that show it
            s.energyMode = name.hasPrefix("lowpower") ? .low : nil
            let image = StatusItemRenderer.image(metrics.filter { $0.text(for: s) != nil }, snapshot: s, settings: settings)
            for dark in [true, false] {
                write(image, dark: dark, to: url.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        settings.resetMenuBar()
        return 0
    }

    private static func write(_ image: NSImage, dark: Bool, to file: URL) {
        let scale: CGFloat = 2, pad: CGFloat = 8
        let size = NSSize(width: image.size.width + pad * 2, height: image.size.height + pad)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(origin: .zero, size: size).fill()
            if image.isTemplate {
                // Template images are tinted by the menu bar; emulate that here
                let tinted = NSImage(size: image.size, flipped: false) { r in
                    image.draw(in: r)
                    NSColor.labelColor.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(at: NSPoint(x: pad, y: pad / 2), from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                image.draw(at: NSPoint(x: pad, y: pad / 2), from: .zero, operation: .sourceOver, fraction: 1)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}

/// `wattsup --render-dashboard <file.png>`: the full dashboard, live data included, as one image,
/// so the lower cards can be checked without scrolling a window.
@MainActor
enum DashboardRender {
    static func run(file: String) -> Int32 {
        let monitor = PowerMonitor()
        let settings = AppSettings()
        monitor.refresh()
        monitor.impact.viewerAppeared()
        // Let the thermals and energy readers finish one pass
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        monitor.refresh()
        let view = DashboardView(monitor: monitor, settings: settings, visibility: MenuBarVisibility(), rendering: true)
            .frame(width: 1040)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not render the dashboard\n".utf8))
            return 1
        }
        do { try png.write(to: URL(fileURLWithPath: file)) } catch { return 1 }
        print("Rendered \(file) at \(Int(image.size.width))x\(Int(image.size.height))")
        return 0
    }
}

/// `wattsup --render-flow-frames <dir> [seconds] [fps]`: the hero and power flow as numbered PNG
/// frames at exact time steps, from live data, for a seamless looping video on the site.
@MainActor
enum FlowFramesRender {
    static func run(directory: String, seconds: Double, fps: Double, warmup: Double = 3) -> Int32 {
        let monitor = MarketingCapture.warmedMonitor(seconds: warmup)
        let settings = AppSettings()
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let count = Int(seconds * fps)
        for i in 0..<count {
            let frame = DemoFrame(time: Double(i) / fps, loop: seconds)
            let view = DashboardView(monitor: monitor, settings: settings, visibility: MenuBarVisibility(),
                                     rendering: true, marketing: true)
                .frame(width: 1040)
                .environment(\.demoFrame, frame)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return 1 }
            try? png.write(to: dir.appendingPathComponent(String(format: "frame_%04d.png", i)))
        }
        print("Rendered \(count) frames to \(directory)")
        return 0
    }
}

/// Shared setup for the site renders: a monitor polled like the app for `seconds`, so the charger
/// verdict, report card and energy ranking have settled before anything is drawn.
@MainActor
enum MarketingCapture {
    static func warmedMonitor(seconds: Double) -> PowerMonitor {
        let monitor = PowerMonitor()
        monitor.impact.viewerAppeared()
        let end = Date().addingTimeInterval(seconds)
        repeat {
            monitor.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(2))
        } while Date() < end
        monitor.refresh()
        return monitor
    }

    static func write<V: View>(_ view: V, width: CGFloat, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .environment(\.colorScheme, .dark)
            .environment(\.themeStyle, Theme.Style(large: true))
            .padding(1)
            .background(Theme.canvas))
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}

/// `wattsup --render-cards <dir> [warmup seconds]`: each dashboard card as its own image, for the site.
@MainActor
enum CardsRender {
    static func run(directory: String, warmup: Double) -> Int32 {
        let m = MarketingCapture.warmedMonitor(seconds: warmup)
        guard let s = m.snapshot else { return 1 }
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let day = m.archive.filter { $0.date >= Date().addingTimeInterval(-86400) }.thinned(to: 400)
        var ok = true
        ok = MarketingCapture.write(ChargerCard(snapshot: s, assessment: m.assessment, quality: m.quality), width: 520,
                                    to: dir.appendingPathComponent("card-charger.png")) && ok
        ok = MarketingCapture.write(BatteryCard(snapshot: s, trend: HealthTrend(points: m.healthPoints)), width: 520,
                                    to: dir.appendingPathComponent("card-battery.png")) && ok
        if let t = s.thermals {
            ok = MarketingCapture.write(ThermalsCard(thermals: t, batteryC: s.temperatureC), width: 520,
                                        to: dir.appendingPathComponent("card-thermals.png")) && ok
        }
        ok = MarketingCapture.write(EnergyCard(days: EnergyAccount.daily(m.archive), price: 0), width: 520,
                                    to: dir.appendingPathComponent("card-energy.png")) && ok
        ok = MarketingCapture.write(EnergyByAppCard(impact: m.impact), width: 620,
                                    to: dir.appendingPathComponent("card-apps.png")) && ok
        ok = MarketingCapture.write(ChargerHistoryCard(chargers: m.chargers.sorted, current: s.adapter?.fingerprint, forget: { _ in }, showsForget: false),
                                    width: 1040, to: dir.appendingPathComponent("card-chargers.png")) && ok
        ok = MarketingCapture.write(Card(title: "History, last 24 hours", symbol: "chart.xyaxis.line") {
            SeriesChart(series: Series.power(day), unit: "W", height: 220, showsZero: true, strideMinutes: 180)
        }, width: 1040, to: dir.appendingPathComponent("card-history.png")) && ok
        if let a = m.assessment {
            ok = MarketingCapture.write(Card(title: "Charger check", symbol: "checkmark.shield") { VerdictBanner(assessment: a) },
                                        width: 520, to: dir.appendingPathComponent("card-check.png")) && ok
        }
        print("Rendered cards to \(directory)" + (ok ? "" : " with errors"))
        return ok ? 0 : 1
    }
}
