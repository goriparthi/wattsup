import SwiftUI
import WattsupCore

/// The battery as a level gauge: the fill is the charge, and a gentle surface moves while
/// power flows, faster the more watts move in or out.
struct BatteryTank: View {
    let snapshot: PowerSnapshot
    var width: CGFloat = 56
    var height: CGFloat = 92
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = AnimationClock()

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
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || !flowing)) { context in
                Canvas { ctx, size in
                    clock.tick(context.date.timeIntervalSinceReferenceDate)
                    draw(in: &ctx, size: size)
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

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.06)))

        // Speed follows the measured watts, so a fast charge visibly churns more
        let speed = min(3, 0.6 + abs(watts) / 20)
        // Accumulated, so the motion speeds up or slows down instead of jumping when watts change
        let wavePhase = clock.value("wave", speed: speed * 2)
        let amplitude = flowing ? max(1, size.height * 0.015) : 0.5
        let surface = size.height * (1 - level)

        var back = Path(), front = Path()
        for (path, phase, scale) in [(0, 0.0, 0.7), (1, 1.7, 1.0)] {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height))
            for x in stride(from: 0, through: size.width, by: 2) {
                let wave = sin((x / size.width) * .pi * 2 + wavePhase + phase)
                p.addLine(to: CGPoint(x: x, y: surface + wave * amplitude * scale))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
            if path == 0 { back = p } else { front = p }
        }
        ctx.fill(back, with: .color(tint.opacity(0.35)))
        ctx.fill(front, with: .color(tint.opacity(0.85)))

    }
}
