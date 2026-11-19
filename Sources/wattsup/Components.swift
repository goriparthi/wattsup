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
    static let surface = Color.primary.opacity(0.045)

    static func battery(_ watts: Double) -> Color { watts < -0.05 ? draining : charging }

    static func verdict(_ v: ChargerAssessment.Verdict) -> Color {
        switch v {
        case .bottleneck, .notKeepingUp: return warning
        case .headroom: return charging
        case .measuring, .unplugged: return .secondary
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
                Image(systemName: symbol).foregroundStyle(Theme.accent)
            }
            .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

struct ChargeRing: View {
    let snapshot: PowerSnapshot
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6

    private var tint: Color {
        snapshot.percent <= 15 && snapshot.state == .discharging ? Theme.warning : Theme.battery(snapshot.batteryWatts)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(snapshot.percent) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: snapshot.symbolName)
                .font(.system(size: size * 0.28))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Battery \(snapshot.percent) percent, \(snapshot.state.title)")
    }
}

/// Charger to Mac to Battery, with watts on each leg.
struct FlowDiagram: View {
    let snapshot: PowerSnapshot
    var large = false

    var body: some View {
        let s = snapshot
        let batteryActive = abs(s.batteryWatts) > 0.05
        HStack(spacing: large ? 10 : 4) {
            FlowNode(symbol: "powerplug.fill", title: "Charger",
                     value: s.isExternalPower ? Units.watts(s.inputWatts) : "Unplugged",
                     detail: s.isExternalPower ? "\(Units.volts(s.inputVolts)) · \(Units.amps(s.inputAmps))" : nil,
                     tint: Theme.input, active: s.isExternalPower, large: large)
            FlowArrow(pointsRight: true, active: s.isExternalPower, large: large)
            FlowNode(symbol: "laptopcomputer", title: "Mac uses",
                     value: Units.watts(s.systemWatts), detail: nil,
                     tint: Theme.system, active: true, large: large)
            FlowArrow(pointsRight: s.batteryWatts >= 0, active: batteryActive, large: large)
            FlowNode(symbol: s.symbolName, title: s.batteryWatts < -0.05 ? "Battery gives" : "Battery gets",
                     value: Units.watts(abs(s.batteryWatts)),
                     detail: "\(Units.volts(s.batteryVolts)) · \(Units.amps(abs(s.batteryAmps)))",
                     tint: Theme.battery(s.batteryWatts), active: batteryActive, large: large)
        }
    }
}

struct FlowNode: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String?
    let tint: Color
    let active: Bool
    let large: Bool

    var body: some View {
        VStack(spacing: large ? 6 : 3) {
            Image(systemName: symbol)
                .font(large ? .title2 : .body)
                .foregroundStyle(active ? tint : .secondary)
            Text(value)
                .font(.system(large ? .title2 : .callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
            if large, let detail {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, large ? 14 : 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(active ? tint.opacity(0.13) : Theme.surface))
        .opacity(active ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

struct FlowArrow: View {
    let pointsRight: Bool
    let active: Bool
    let large: Bool

    var body: some View {
        Image(systemName: pointsRight ? "chevron.right" : "chevron.left")
            .font(large ? .title3.weight(.semibold) : .caption.weight(.bold))
            .foregroundStyle(active ? Color.secondary : Color.secondary.opacity(0.3))
            .symbolEffect(.pulse, isActive: active)
            .accessibilityHidden(true)
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
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsAdvisories {
                ForEach(assessment.advisories, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.1)))
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
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: height)
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
            .foregroundStyle(.secondary)
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
                    Text("Cell \(i + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
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
    }
}
