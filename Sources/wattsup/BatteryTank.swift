import SwiftUI
import WattsupCore

/// The battery as a tank of liquid: the level is the charge, the surface moves, bubbles rise
/// while charging and drops fall while draining, faster the more watts flow.
struct BatteryTank: View {
    let snapshot: PowerSnapshot
    var width: CGFloat = 56
    var height: CGFloat = 92
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Double { Double(snapshot.percent) / 100 }
    private var watts: Double { snapshot.batteryWatts }
    private var flowing: Bool { abs(watts) > 0.3 }
    private var tint: Color {
        if snapshot.state == .discharging && snapshot.percent <= 15 { return Theme.warning }
        return watts < -0.05 ? Theme.draining : Theme.charging
    }

    var body: some View {
        VStack(spacing: 0) {
            // Terminal cap on top, like a battery standing upright
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(0.35))
                .frame(width: width * 0.36, height: height * 0.06)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !flowing)) { context in
                Canvas { ctx, size in
                    draw(in: &ctx, size: size, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2))
        }
        .accessibilityElement()
        .accessibilityLabel("Battery \(snapshot.percent) percent, \(snapshot.state.title)")
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.06)))

        // Speed follows the measured watts, so a fast charge visibly churns more
        let speed = min(3, 0.6 + abs(watts) / 20)
        let amplitude = flowing ? max(1.5, size.height * 0.03) : 1
        let surface = size.height * (1 - level)

        var back = Path(), front = Path()
        for (path, phase, scale) in [(0, 0.0, 0.7), (1, 1.7, 1.0)] {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height))
            for x in stride(from: 0, through: size.width, by: 2) {
                let wave = sin((x / size.width) * .pi * 2 + time * speed * 2 + phase)
                p.addLine(to: CGPoint(x: x, y: surface + wave * amplitude * scale))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
            if path == 0 { back = p } else { front = p }
        }
        ctx.fill(back, with: .color(tint.opacity(0.35)))
        ctx.fill(front, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.95), tint.opacity(0.7)]),
            startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: size.height)))

        guard flowing, level > 0.04 else { return }
        let liquidHeight = size.height - surface
        for i in 0..<6 {
            let seed = Double(i) * 0.618
            let x = size.width * (0.15 + 0.7 * (seed.truncatingRemainder(dividingBy: 1)))
            let progress = (time * speed * 0.35 + seed).truncatingRemainder(dividingBy: 1)
            let r = 1.5 + Double(i % 3)
            // Charging: bubbles rise to the surface. Draining: drops fall from it.
            let y = watts > 0
                ? size.height - progress * liquidHeight
                : surface + progress * liquidHeight
            let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(.white.opacity(0.35 * (1 - progress) + 0.1)))
        }
    }
}
