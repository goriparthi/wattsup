import AppKit
import SwiftUI
import WattsupCore

/// Brand tokens from brand/BRAND.md, each resolving to its light or dark value.
enum Brand {
    static let iris = dynamic(0x4835A5, 0xC5B8FF)
    static let citron = dynamic(0x3D6418, 0xD8F98B)
    static let input = dynamic(0x254EAF, 0x8EB1FF)
    static let system = dynamic(0x65439B, 0xCFB2FF)
    static let charging = dynamic(0x00634F, 0x7CE1B5)
    static let draining = dynamic(0x8F3768, 0xFFA9D5)
    static let warning = dynamic(0x855006, 0xFFCA75)
    static let textPrimary = dynamic(0x171A2C, 0xF3F5FE)
    static let textSecondary = dynamic(0x4D5770, 0xB2BAD4)
    /// Brighter secondary text for the dashboard, where the user asked for more contrast
    static let textSecondaryStrong = dynamic(0x3A4258, 0xCDD3E6)
    static let canvas = dynamic(0xF4F6FB, 0x111427)
    static let elevated = dynamic(0xFFFFFF, 0x1C2138)

    static func color(_ tone: MetricTone) -> NSColor {
        switch tone {
        case .input: return input
        case .system: return system
        case .charging: return charging
        case .draining: return draining
        case .warning: return warning
        case .neutral: return .labelColor
        }
    }

    private static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(_ brand: NSColor) { self.init(nsColor: brand) }
}

/// The brand's 18 pt menu bar glyphs: one battery silhouette, a different interior per state.
/// Drawn from the spec's geometry so they stay crisp at every scale.
enum BrandGlyph {
    case charging, discharging, full, held, noBattery

    init(_ state: ChargeState) {
        switch state {
        case .charging: self = .charging
        case .discharging: self = .discharging
        case .full: self = .full
        case .held: self = .held
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .charging: return "Charging"
        case .discharging: return "Discharging"
        case .full: return "Fully charged on AC"
        case .held: return "Plugged in, charging on hold"
        case .noBattery: return "No battery detected"
        }
    }

    /// Black template artwork on an 18 by 18 point canvas, tinted by the caller when colored.
    func image(tint: NSColor? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            (tint ?? .black).setFill()
            let shell = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 14, height: 10), xRadius: 2.5, yRadius: 2.5)
            shell.append(NSBezierPath(roundedRect: NSRect(x: 2.5, y: 5.5, width: 11, height: 7), xRadius: 1, yRadius: 1))
            shell.windingRule = .evenOdd
            shell.fill()
            let terminal = NSBezierPath()
            terminal.move(to: NSPoint(x: 15, y: 7))
            terminal.line(to: NSPoint(x: 16, y: 7))
            terminal.appendArc(from: NSPoint(x: 17, y: 7), to: NSPoint(x: 17, y: 8), radius: 1)
            terminal.line(to: NSPoint(x: 17, y: 10))
            terminal.appendArc(from: NSPoint(x: 17, y: 11), to: NSPoint(x: 16, y: 11), radius: 1)
            terminal.line(to: NSPoint(x: 15, y: 11))
            terminal.close()
            terminal.fill()
            interior().fill()
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    private func interior() -> NSBezierPath {
        switch self {
        case .charging:
            return polygon([(4.5, 8.8), (8, 5.9), (11.5, 8.8), (9.1, 8.8), (9.1, 12.1), (6.9, 12.1), (6.9, 8.8)])
        case .discharging:
            return polygon([(4.5, 9.2), (6.9, 9.2), (6.9, 5.9), (9.1, 5.9), (9.1, 9.2), (11.5, 9.2), (8, 12.1)])
        case .full:
            return NSBezierPath(roundedRect: NSRect(x: 3.5, y: 6.5, width: 9, height: 5), xRadius: 0.65, yRadius: 0.65)
        case .held:
            let bars = NSBezierPath(roundedRect: NSRect(x: 5.6, y: 6.6, width: 1.6, height: 4.8), xRadius: 0.35, yRadius: 0.35)
            bars.append(NSBezierPath(roundedRect: NSRect(x: 8.8, y: 6.6, width: 1.6, height: 4.8), xRadius: 0.35, yRadius: 0.35))
            return bars
        case .noBattery:
            return polygon([(5.25, 7.15), (6.35, 6.05), (8, 7.7), (9.65, 6.05), (10.75, 7.15), (9.1, 8.8),
                            (10.75, 10.45), (9.65, 11.55), (8, 9.9), (6.35, 11.55), (5.25, 10.45), (6.9, 8.8)])
        }
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].0, y: points[0].1))
        points.dropFirst().forEach { path.line(to: NSPoint(x: $0.0, y: $0.1)) }
        path.close()
        return path
    }
}
