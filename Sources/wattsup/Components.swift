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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.secondaryText)
            }
            .font(.headline)
            content
        }
        .padding(14)
        // Fills the row height too, so cards side by side end on the same line
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
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

struct CellBars: View {
    let cells: [Double]

    var body: some View {
        // Lithium cells sit between roughly 3.0 V empty and 4.4 V full
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, v in
                HStack(spacing: 8) {
                    Text("Cell \(i + 1)").font(.caption).foregroundStyle(Theme.secondaryText).frame(width: 44, alignment: .leading)
                    LoadBarTinted(fraction: (v - 3.0) / 1.4, tint: Theme.charging)
                    Text(Units.volts(v, digits: 3)).font(.caption.monospacedDigit()).frame(width: 58, alignment: .trailing)
                }
            }
        }
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
