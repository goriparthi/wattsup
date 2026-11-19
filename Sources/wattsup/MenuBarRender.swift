import AppKit
import WattsupCore

/// `wattsup --render-menubar <dir>`: draws the readout in each layout from a live reading,
/// on light and dark bars, so the status item can be checked without the real menu bar.
@MainActor
enum MenuBarRender {
    static func run(directory: String) -> Int32 {
        guard case .properties(let props) = SmartBattery.read(), let s = PowerSnapshot(registry: props) else {
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
        ]
        for (name, metrics, layout, icon, colors) in cases {
            settings.metrics = metrics
            settings.layout = layout
            settings.icon = icon
            settings.usesColors = colors
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
