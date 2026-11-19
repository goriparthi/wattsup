import Charts
import SwiftUI
import WattsupCore

/// SwiftUI face of the brand tokens in Brand.swift; every view reads color from here.
enum Theme {
    static let input = Color(Brand.input)
    static let system = Color(Brand.system)
    static let charging = Color(Brand.charging)
    static let draining = Color(Brand.draining)
    static let warning = Color(Brand.warning)
    static let accent = Color(Brand.iris)
    static let surface = Color(Brand.elevated)
    static let canvas = Color(Brand.canvas)
    /// Brand secondary text: higher contrast than the system gray, AA on both surfaces
    static let secondaryText = Color(Brand.textSecondary)
    static let hairline = Color.primary.opacity(0.1)

    /// Type and contrast for a context: the dashboard reads larger and brighter than the popover.
    struct Style: Sendable {
        var large = false
        var body: Font { large ? .system(size: 14) : .callout }
        var caption: Font { large ? .system(size: 12) : .caption }
        var title: Font { large ? .system(size: 15, weight: .semibold) : .headline }
        var secondary: Color { large ? Color(Brand.textSecondaryStrong) : Theme.secondaryText }
        var hairline: Color { large ? Color.primary.opacity(0.18) : Theme.hairline }
    }

    static func battery(_ watts: Double) -> Color { watts < -0.05 ? draining : charging }

    static func verdict(_ v: ChargerAssessment.Verdict) -> Color {
        switch v {
        case .bottleneck, .notKeepingUp: return warning
        case .headroom: return charging
        case .measuring, .unplugged, .negotiating: return .secondary
        }
    }

    static func load(_ fraction: Double) -> Color {
        fraction >= 0.9 ? warning : fraction >= 0.75 ? draining : input
    }
}

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content
    @Environment(\.themeStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(style.secondary)
            }
            .font(style.title)
            content
        }
        .padding(14)
        // Fills the row height too, so cards side by side end on the same line
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style.hairline, lineWidth: 1))
    }
}

private struct ThemeStyleKey: EnvironmentKey { static let defaultValue = Theme.Style() }

extension EnvironmentValues {
    var themeStyle: Theme.Style {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var tint: Color? = nil
    @Environment(\.themeStyle) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(style.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .font(style.body)
    }
}

struct VerdictBanner: View {
    let assessment: ChargerAssessment
    var showsAdvisories = true

    private var symbol: String {
        switch assessment.verdict {
        case .bottleneck: return "gauge.with.dots.needle.100percent"
        case .notKeepingUp: return "exclamationmark.triangle.fill"
        case .headroom: return "checkmark.seal.fill"
        case .measuring: return "hourglass"
        case .negotiating: return "arrow.triangle.2.circlepath"
        case .unplugged: return "battery.100percent"
        }
    }

    var body: some View {
        let tint = Theme.verdict(assessment.verdict)
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(assessment.headline).font(.callout.weight(.semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(assessment.detail)
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showsAdvisories {
                ForEach(assessment.advisories, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Neutral panel with a thin status edge, instead of a tinted block
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04))
                Rectangle().fill(tint).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct LoadBar: View {
    let fraction: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(Theme.load(fraction))
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Load \(Units.percent(fraction))")
    }
}

/// Each series also carries its brand line pattern, so traces read without color.
struct LineSeries: Identifiable {
    let name: String
    let color: Color
    var dash: [CGFloat] = []
    let points: [(date: Date, value: Double)]
    var id: String { name }

    enum Pattern {
        static let input: [CGFloat] = []
        static let system: [CGFloat] = [8, 4]
        static let charging: [CGFloat] = [1, 5]
        static let draining: [CGFloat] = [7, 4, 1, 4]
        static let warning: [CGFloat] = [13, 5]
    }
}

struct SeriesChart: View {
    let series: [LineSeries]
    let unit: String
    var height: CGFloat = 160
    var showsZero = false
    var showsLegend = true
    var strideMinutes = 1

    private var accessibilitySummary: String {
        let parts = series.compactMap { s in s.points.last.map { "\(s.name) \(String(format: "%g", ($0.value * 10).rounded() / 10)) \(unit)" } }
        return parts.isEmpty ? "Chart, no data yet" : "Chart, latest: " + parts.joined(separator: ", ")
    }

    var body: some View {
        Chart {
            ForEach(series) { s in
                ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Time", p.date), y: .value(unit, p.value),
                             series: .value("Series", s.name))
                        .foregroundStyle(by: .value("Series", s.name))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: s.dash))
                        .interpolationMethod(.monotone)
                }
            }
            if showsZero {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.4))
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(showsLegend ? .visible : .hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(v, specifier: "%g") \(unit)") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: strideMinutes)) { _ in
                AxisGridLine()
                // Week long ranges label days; shorter ones label the time
                if strideMinutes >= 1440 {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
                } else {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
        .frame(height: height)
        // VoiceOver hears the latest value of each line instead of an unlabeled chart
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}

enum Series {
    static func power(_ samples: [PowerSample]) -> [LineSeries] {
        let draining = (samples.last?.batteryWatts ?? 0) < -0.05
        return [
            LineSeries(name: "Charger", color: Theme.input, dash: LineSeries.Pattern.input,
                       points: samples.map { ($0.date, $0.inputWatts) }),
            LineSeries(name: "Mac", color: Theme.system, dash: LineSeries.Pattern.system,
                       points: samples.map { ($0.date, $0.systemWatts) }),
            LineSeries(name: "Battery", color: draining ? Theme.draining : Theme.charging,
                       dash: draining ? LineSeries.Pattern.draining : LineSeries.Pattern.charging,
                       points: samples.map { ($0.date, $0.batteryWatts) }),
        ]
    }
}

struct ProfileTable: View {
    let adapter: AdapterInfo

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Profile"); Text("Voltage"); Text("Current"); Text("Power")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            ForEach(adapter.profiles) { p in
                let active = p.index == adapter.activeProfileIndex
                GridRow {
                    Label(active ? "In use" : "PDO \(p.index + 1)",
                          systemImage: active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(active ? Theme.input : .secondary)
                    Text(Units.volts(p.volts, digits: 1))
                    Text(Units.amps(p.amps))
                    Text(Units.watts(p.watts, digits: 0))
                }
                .font(.callout.monospacedDigit())
                .fontWeight(active ? .semibold : .regular)
            }
        }
    }
}

/// The pack drawn as a battery with one compartment per cell, each filled to its own level.
/// Lithium cells run from about 3.0 V empty to 4.35 V full; the fill maps that range.
struct CellPack: View {
    let cells: [Double]
    var charging = false
    @Environment(\.themeStyle) private var style

    private func level(_ v: Double) -> Double { min(1, max(0, (v - 3.0) / 1.35)) }

    var body: some View {
        let tint = charging ? Theme.charging : Theme.charging.opacity(0.85)
        let lo = cells.min() ?? 0, hi = cells.max() ?? 0
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, v in
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06))
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tint)
                                    .frame(height: geo.size.height * level(v))
                                    .animation(.smooth(duration: 0.8), value: v)
                            }
                        }
                    }
                }
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style.secondary.opacity(0.6), lineWidth: 2))
                // Terminal on the right, like a pack lying on its side
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(style.secondary.opacity(0.6))
                    .frame(width: 5, height: 22)
            }
            .frame(height: 64)
            HStack(spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 1) {
                        Text(Units.volts(v, digits: 3)).font(style.caption.monospacedDigit())
                            // The lowest and highest cell are marked so imbalance is visible at a glance
                            .foregroundStyle(cells.count > 1 && (v == lo || v == hi) && hi - lo > 0.02 ? Theme.warning : .primary)
                        Text("Cell \(i + 1)").font(style.caption).foregroundStyle(style.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cells: " + cells.enumerated().map { "cell \($0.offset + 1) \(Units.volts($0.element, digits: 2))" }.joined(separator: ", "))
    }
}

/// A fan that spins at a speed following its rpm and stands still when the fan is off.
struct SpinningFan: View {
    let rpm: Double
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = AnimationClock()
    @Environment(\.demoFrame) private var demoFrame

    var body: some View {
        let running = rpm > 50
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !running || reduceMotion)) { context in
            // Visual turns per second, scaled down from real rpm so it reads as speed, not blur
            let _ = { clock.demo = demoFrame; clock.tick(context.date.timeIntervalSinceReferenceDate) }()
            let angle = running ? clock.value("fan", speed: 0.4 + rpm / 2500) * 360 : 0
            Image(systemName: "fan")
                .font(.system(size: size, weight: .regular))
                .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
                .foregroundStyle(running ? Theme.system : Theme.secondaryText.opacity(0.6))
        }
        .frame(width: size + 6, height: size + 6)
        .accessibilityHidden(true)
    }
}

struct LoadBarTinted: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue(Units.percent(fraction))
    }
}

/// Energy Mode for one power source. Compact is a single menu row for the popover.
struct EnergyModePicker: View {
    let energy: EnergyModeController
    let source: PowerSource
    let compact: Bool

    var body: some View {
        if let modes = energy.modes, let current = modes.mode(for: source) {
            let binding = Binding(get: { current }, set: { energy.set($0, for: source) })
            if compact {
                HStack {
                    Text("Energy mode").foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Picker("Energy mode", selection: binding) {
                        ForEach(modes.available) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(energy.busy)
                }
                .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.title).font(.caption).foregroundStyle(Theme.secondaryText)
                    Picker(source.title, selection: binding) {
                        ForEach(modes.available) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(energy.busy)
                    if let error = energy.error {
                        Text(error).font(.caption).foregroundStyle(Theme.warning)
                    }
                }
            }
        }
    }
}

/// A pill shown while Low or High Power Mode is on; nothing in Automatic.
struct EnergyModeBadge: View {
    let mode: EnergyMode?

    var body: some View {
        if let mode, mode != .automatic {
            let tint = mode == .low ? Theme.warning : Theme.accent
            Label(mode.title, systemImage: mode == .low ? "leaf.fill" : "bolt.circle.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint.opacity(0.16)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
                .foregroundStyle(tint)
                .accessibilityLabel("\(mode.title) Mode on")
        }
    }
}
