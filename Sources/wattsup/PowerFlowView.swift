import SwiftUI
import WattsupCore

/// Hybrid car style energy monitor: glowing nodes joined by pipes whose thickness follows the
/// watts and whose particles stream in the real direction of flow.
struct PowerFlowView: View {
    let snapshot: PowerSnapshot
    var large = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = AnimationClock()

    private struct Link {
        var from: CGPoint, to: CGPoint
        var watts: Double
        var tint: Color
        var label: String
    }

    var body: some View {
        let s = snapshot
        GeometryReader { geo in
            let layout = Layout(size: geo.size, large: large, accessories: !s.peripherals.isEmpty)
            let links = links(layout)
            ZStack {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                    Canvas { ctx, _ in
                        clock.tick(context.date.timeIntervalSinceReferenceDate)
                        for (i, link) in links.enumerated() { drawPipe(link, key: "pipe\(i)", in: &ctx) }
                    }
                }
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    if link.watts > 0.05 {
                        WattBadge(text: link.label, tint: link.tint, large: large)
                            .position(x: (link.from.x + link.to.x) / 2,
                                      y: (link.from.y + link.to.y) / 2 - (link.from.y == link.to.y ? layout.radius * 0.62 : 0))
                            .offset(x: link.from.y == link.to.y ? 0 : layout.radius * 1.2)
                    }
                }
                FlowNodeBadge(symbol: "powerplug.fill", title: "Charger",
                              value: s.isExternalPower ? Units.watts(s.inputWatts) : "Unplugged",
                              detail: s.isExternalPower ? "\(Units.volts(s.inputVolts)) · \(Units.amps(s.inputAmps))" : nil,
                              tint: Theme.input, active: s.isExternalPower, ring: nil, layout: layout)
                    .position(layout.charger)
                FlowNodeBadge(symbol: "laptopcomputer", title: "Mac uses", value: Units.watts(s.systemWatts),
                              detail: s.energyMode.flatMap { $0 == .automatic ? nil : $0.title },
                              tint: Theme.system, active: true, ring: nil, layout: layout)
                    .position(layout.mac)
                FlowNodeBadge(symbol: s.symbolName, title: "Battery \(s.percent)%",
                              value: Units.watts(s.batteryWatts, signed: true),
                              detail: "\(Units.volts(s.batteryVolts)) · \(Units.amps(abs(s.busAmpsForBattery)))",
                              tint: batteryTint, active: abs(s.batteryWatts) > 0.05,
                              ring: Double(s.percent) / 100, layout: layout)
                    .position(layout.battery)
                if let p = s.peripherals.first, let point = layout.accessories {
                    FlowNodeBadge(symbol: p.symbolName,
                                  title: s.peripherals.count == 1 ? p.name : "\(s.peripherals.count) devices",
                                  value: "up to \(Units.watts(s.peripherals.allocatedWatts, digits: 0))", detail: nil,
                                  tint: Theme.system, active: true, ring: nil, layout: layout)
                        .position(point)
                }
            }
        }
        .frame(height: Layout.height(large: large, accessories: !snapshot.peripherals.isEmpty))
        .accessibilityElement(children: .combine)
    }

    private var batteryTint: Color {
        if snapshot.state == .discharging && snapshot.percent <= 15 { return Theme.warning }
        return snapshot.batteryWatts < -0.05 ? Theme.draining : Theme.charging
    }

    private func links(_ l: Layout) -> [Link] {
        let s = snapshot
        var out = [Link(from: l.edge(l.charger, toward: l.mac), to: l.edge(l.mac, toward: l.charger),
                        watts: s.isExternalPower ? (s.inputWatts ?? 0) : 0, tint: Theme.input,
                        label: Units.watts(s.inputWatts))]
        // Charging flows Mac to battery; draining flows battery to Mac
        let b = s.batteryWatts
        let macEdge = l.edge(l.mac, toward: l.battery), batteryEdge = l.edge(l.battery, toward: l.mac)
        out.append(Link(from: b >= 0 ? macEdge : batteryEdge, to: b >= 0 ? batteryEdge : macEdge,
                        watts: abs(b), tint: batteryTint, label: Units.watts(abs(b))))
        if let a = l.accessories {
            // Starts under the Mac's labels so the pipe never runs through the text
            let start = CGPoint(x: l.mac.x, y: l.mac.y + l.radius + (l.large ? 70 : 50))
            out.append(Link(from: start, to: l.edge(a, toward: l.mac),
                            watts: s.peripherals.allocatedWatts, tint: Theme.system,
                            label: "≤ " + Units.watts(s.peripherals.allocatedWatts, digits: 0)))
        }
        return out
    }

    private func drawPipe(_ link: Link, key: String, in ctx: inout GraphicsContext) {
        var path = Path()
        path.move(to: link.from)
        path.addLine(to: link.to)
        guard link.watts > 0.05 else {
            ctx.stroke(path, with: .color(Color.secondary.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
            return
        }
        let width = (large ? 5 : 3.5) + min(large ? 12 : 7, link.watts / (large ? 6 : 9))
        ctx.stroke(path, with: .color(link.tint.opacity(0.18)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        ctx.stroke(path, with: .color(link.tint.opacity(0.55)), style: StrokeStyle(lineWidth: max(1.5, width * 0.28), lineCap: .round))

        let dx = link.to.x - link.from.x, dy = link.to.y - link.from.y
        let length = max(1, hypot(dx, dy))
        if reduceMotion {
            drawArrow(at: CGPoint(x: link.from.x + dx * 0.5, y: link.from.y + dy * 0.5),
                      angle: atan2(dy, dx), tint: link.tint, in: &ctx)
            return
        }
        // A fixed particle count keeps motion steady; the watts set speed, size and glow instead
        let count = 7
        let intensity = min(1, 0.35 + link.watts / 60)
        let speed = (0.25 + min(1.6, link.watts / 45)) * (140 / length)
        let base = clock.phase(key, speed: speed)
        let r = width * (0.3 + 0.15 * intensity)
        let tail = min(0.12, 18 / length)

        func point(_ p: Double) -> CGPoint { CGPoint(x: link.from.x + dx * p, y: link.from.y + dy * p) }
        func fade(_ p: Double) -> Double { sin(.pi * min(1, max(0, p))) }

        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: large ? 2.5 : 1.8))
            for i in 0..<count {
                let p = (base + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                // Comet tail: a short streak behind each particle, fading toward its end
                var streak = Path()
                streak.move(to: point(max(0, p - tail)))
                streak.addLine(to: point(p))
                layer.stroke(streak, with: .color(link.tint.opacity(0.6 * fade(p) * intensity)),
                             style: StrokeStyle(lineWidth: r * 1.4, lineCap: .round))
                let pt = point(p)
                layer.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                           with: .color(link.tint.opacity(fade(p))))
            }
        }
        for i in 0..<count {
            let p = (base + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let pt = point(p), core = r * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - core, y: pt.y - core, width: core * 2, height: core * 2)),
                     with: .color(.white.opacity(0.9 * fade(p))))
        }
    }

    private func drawArrow(at p: CGPoint, angle: CGFloat, tint: Color, in ctx: inout GraphicsContext) {
        var arrow = Path()
        arrow.move(to: CGPoint(x: 6, y: 0))
        arrow.addLine(to: CGPoint(x: -4, y: -5))
        arrow.addLine(to: CGPoint(x: -4, y: 5))
        arrow.closeSubpath()
        ctx.fill(arrow.applying(CGAffineTransform(rotationAngle: angle).concatenating(
            CGAffineTransform(translationX: p.x, y: p.y))), with: .color(tint))
    }

    struct Layout {
        let size: CGSize
        let large: Bool
        let radius: CGFloat
        let charger, mac, battery: CGPoint
        let accessories: CGPoint?

        static func height(large: Bool, accessories: Bool) -> CGFloat {
            (large ? 190 : 128) + (accessories ? (large ? 160 : 118) : 0)
        }

        init(size: CGSize, large: Bool, accessories: Bool) {
            self.size = size
            self.large = large
            radius = large ? 30 : 20
            let y: CGFloat = large ? 70 : 46
            let inset = large ? size.width * 0.14 : size.width * 0.15
            charger = CGPoint(x: inset, y: y)
            mac = CGPoint(x: size.width / 2, y: y)
            battery = CGPoint(x: size.width - inset, y: y)
            // Room below the accessory node for its circle and two or three label lines
            self.accessories = accessories ? CGPoint(x: size.width / 2, y: size.height - (large ? 100 : 66)) : nil
        }

        func edge(_ a: CGPoint, toward b: CGPoint) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let d = max(1, hypot(dx, dy))
            let gap = radius + (large ? 6 : 4)
            return CGPoint(x: a.x + dx / d * gap, y: a.y + dy / d * gap)
        }
    }
}

private struct FlowNodeBadge: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String?
    let tint: Color
    let active: Bool
    let ring: Double?
    let layout: PowerFlowView.Layout

    var body: some View {
        let r = layout.radius
        VStack(spacing: layout.large ? 5 : 3) {
            ZStack {
                // The ring, when present, takes the outer band so every node keeps the same footprint
                let ringWidth: CGFloat = layout.large ? 4 : 3
                let inset: CGFloat = ring == nil ? 0 : ringWidth + 3
                Group {
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(active ? 0.45 : 0.12), tint.opacity(active ? 0.12 : 0.04)],
                                             center: .center, startRadius: 0, endRadius: r))
                    Circle().strokeBorder(tint.opacity(active ? 0.8 : 0.25), lineWidth: 1.5)
                }
                .padding(inset)
                if let ring {
                    Circle().stroke(tint.opacity(0.2), lineWidth: ringWidth).padding(ringWidth / 2)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(tint, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(ringWidth / 2)
                }
                Image(systemName: symbol)
                    .font(.system(size: r * (ring == nil ? 0.72 : 0.6), weight: .semibold))
                    .foregroundStyle(active ? tint : .secondary)
            }
            .frame(width: r * 2, height: r * 2)
            .shadow(color: active ? tint.opacity(0.55) : .clear, radius: layout.large ? 12 : 7)
            Text(value)
                .font(.system(layout.large ? .title3 : .callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.6), value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
            if layout.large, let detail {
                Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: layout.large ? 150 : 104)
        .offset(y: (layout.large ? 34 : 24))
    }
}

private struct WattBadge: View {
    let text: String
    let tint: Color
    let large: Bool

    var body: some View {
        Text(text)
            .font(.system(large ? .caption : .caption2, design: .monospaced).weight(.semibold))
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.6), value: text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.background.opacity(0.85)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
            .foregroundStyle(tint)
    }
}

extension PowerSnapshot {
    /// Pack current that agrees with the battery watts shown, including right after unplugging.
    var busAmpsForBattery: Double {
        batteryVolts > 0 ? batteryWatts / batteryVolts : batteryAmps
    }
}
