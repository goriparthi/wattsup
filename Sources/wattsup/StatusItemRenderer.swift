import AppKit
import WattsupCore

/// Draws the status item as one image: an outlined capsule holding the icon and readings,
/// with hairline dividers between readings, on one line or two rows.
@MainActor
enum StatusItemRenderer {
    static let height: CGFloat = 22
    private static let padding: CGFloat = 5
    private static let gap: CGFloat = 4

    static func color(_ tone: MetricTone, colored: Bool) -> NSColor {
        colored ? Brand.color(tone) : .labelColor
    }

    static func apply(to button: NSStatusBarButton, snapshot s: PowerSnapshot?, settings: AppSettings) {
        button.attributedTitle = NSAttributedString()
        button.imagePosition = .imageOnly
        guard let s else {
            button.image = BrandGlyph.noBattery.image()
            return
        }
        let readings = settings.metrics.filter { $0.text(for: s) != nil }
        button.image = image(readings, snapshot: s, settings: settings)
        button.setAccessibilityLabel("Wattsup, \(s.statusLine), \(MenuBarMetric.line(readings, for: s))")
    }

    static func image(_ readings: [MenuBarMetric], snapshot s: PowerSnapshot, settings: AppSettings) -> NSImage {
        let stacked = settings.layout == .stacked && readings.count > 1
        let fontSize: CGFloat = stacked ? 9 : 12
        let rows = (stacked ? MenuBarMetric.rows(readings) : [readings]).map { row in
            row.compactMap { metric -> NSAttributedString? in
                metric.text(for: s).map {
                    NSAttributedString(string: $0, attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                        .foregroundColor: color(metric.tone(for: s), colored: settings.usesColors),
                    ])
                }
            }
        }
        let style = readings.isEmpty && settings.icon == .none ? .power : settings.icon
        let symbol = icon(for: s, style: style, colored: settings.usesColors)
        let outlined = settings.outlined && !readings.isEmpty

        // Column widths shared by both rows, so stacked dividers line up
        let columns = rows.map(\.count).max() ?? 0
        let columnWidths = (0..<columns).map { c in
            rows.compactMap { c < $0.count ? ceil($0[c].size().width) : nil }.max() ?? 0
        }
        let textWidth = columnWidths.reduce(0, +) + CGFloat(max(0, columns - 1)) * (gap * 2 + 1)
        let iconWidth = symbol.map { ceil($0.size.width) + (readings.isEmpty ? 0 : gap) } ?? 0
        let inset = outlined ? padding : 0
        let size = NSSize(width: inset * 2 + iconWidth + textWidth, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            if outlined {
                let pill = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 2.5, width: size.width - 1, height: height - 5),
                                        xRadius: 5, yRadius: 5)
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                pill.fill()
                NSColor.labelColor.withAlphaComponent(0.35).setStroke()
                pill.lineWidth = 1
                pill.stroke()
            }
            var x = inset
            if let symbol {
                let sz = symbol.size
                symbol.draw(in: NSRect(x: x, y: (height - sz.height) / 2, width: sz.width, height: sz.height))
                x += iconWidth
            }
            let lineHeight = rows.first?.first?.size().height ?? 12
            for (r, row) in rows.enumerated() {
                let y = stacked ? (r == 0 ? 10.5 : 1.5) : (height - lineHeight) / 2
                var cx = x
                for (i, text) in row.enumerated() {
                    if i > 0 {
                        // Hairline divider between readings
                        NSColor.labelColor.withAlphaComponent(0.3).setFill()
                        NSRect(x: cx + gap, y: y + 2, width: 1, height: text.size().height - 4).fill()
                        cx += gap * 2 + 1
                    }
                    text.draw(at: NSPoint(x: cx, y: y))
                    cx += columnWidths[i]
                }
            }
            return true
        }
        // Template only when nothing is colored, so plain mode adapts to any menu bar
        image.isTemplate = !settings.usesColors
        return image
    }

    static func icon(for s: PowerSnapshot, style: MenuBarIcon, colored: Bool) -> NSImage? {
        switch style {
        case .none: return nil
        case .battery:
            return BrandGlyph(s.state).image(tint: colored ? color(s.symbolTone, colored: true) : .labelColor)
        case .power: break
        }
        let name = s.powerSymbolName
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: s.state.title)?
            .withSymbolConfiguration(config)
        // Drawn into the image by hand, so a neutral icon needs an explicit label color
        guard colored else { return base }
        return base?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [color(s.symbolTone, colored: true)]))
    }
}
