import SwiftUI
import WattsupCore

/// The full detail window: everything the battery controller and charger report.
struct DashboardView: View {
    let monitor: PowerMonitor
    let settings: AppSettings
    let visibility: MenuBarVisibility
    @State private var range: ChartRange = .fifteen
    @State private var mode: ChartMode = .power

    var body: some View {
        ScrollView {
            if let s = monitor.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    if visibility.hidden {
                        Label {
                            Text("macOS is hiding the Wattsup readout because the menu bar is full or the notch covers it. Command drag a few items out of the menu bar to make room.")
                        } icon: {
                            Image(systemName: "eye.slash")
                        }
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warning.opacity(0.12)))
                    }
                    hero(s)
                    // The side column stacks the short cards so it fills the flow's height
                    HStack(alignment: .top, spacing: 16) {
                        Card(title: "Power flow", symbol: "arrow.left.arrow.right") {
                            Spacer(minLength: 0)
                            PowerFlowView(snapshot: s, large: true)
                            Spacer(minLength: 0)
                        }
                        VStack(spacing: 16) {
                            Card(title: "Charger check", symbol: "checkmark.shield") {
                                if let a = monitor.assessment { VerdictBanner(assessment: a) }
                            }
                            Card(title: "Energy mode", symbol: "leaf") {
                                EnergyModePicker(energy: monitor.energy, source: .battery, compact: false)
                                EnergyModePicker(energy: monitor.energy, source: .charger, compact: false)
                                Text("Changing it asks for an administrator password, because macOS only lets an admin change power settings.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !s.peripherals.isEmpty {
                                AccessoriesCard(peripherals: s.peripherals, compact: true)
                            }
                        }
                        .frame(width: 360)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    charts
                    HStack(alignment: .top, spacing: 16) {
                        ChargerCard(snapshot: s, assessment: monitor.assessment, quality: monitor.quality)
                        BatteryCard(snapshot: s)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    ChargerHistoryCard(chargers: monitor.chargers.sorted,
                                       current: s.adapter?.fingerprint,
                                       forget: monitor.forgetCharger)
                }
                .padding(20)
            } else {
                UnavailableView(availability: monitor.availability).padding(40)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Theme.canvas)
        .tint(Theme.accent)
    }

    private func hero(_ s: PowerSnapshot) -> some View {
        HStack(spacing: 20) {
            BatteryTank(snapshot: s, width: 54, height: 86)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.percent)%")
                    .font(.system(size: 36, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 8) {
                    Text(s.statusLine).font(.title3).foregroundStyle(Theme.secondaryText)
                    EnergyModeBadge(mode: s.energyMode)
                }
            }
            Spacer()
            HeroStat(title: "Charger in", symbol: "powerplug.fill", value: s.isExternalPower ? Units.watts(s.inputWatts) : "Unplugged",
                     detail: s.isExternalPower ? "\(Units.volts(s.inputVolts)) · \(Units.amps(s.inputAmps))" : "On battery",
                     tint: s.isExternalPower ? Theme.input : .secondary)
            HeroStat(title: "Mac uses", symbol: "laptopcomputer", value: Units.watts(s.systemWatts), detail: "System load", tint: Theme.system)
            HeroStat(title: "Battery", symbol: s.batteryNodeSymbol, value: Units.watts(s.batteryWatts, signed: true),
                     detail: "\(Units.volts(s.batteryVolts)) · \(Units.amps(s.batteryAmps))",
                     tint: Theme.battery(s.batteryWatts))
            if let wall = s.wallWatts {
                HeroStat(title: "From the wall", symbol: "poweroutlet.type.b.fill", value: Units.watts(wall), detail: "Estimated", tint: .secondary)
            }
        }
    }

    private var charts: some View {
        let samples = range.usesArchive
            ? monitor.archive.filter { $0.date >= Date().addingTimeInterval(-range.seconds) }.thinned(to: 400)
            : monitor.history.recent(range.seconds).thinned(to: 400)
        return Card(title: "History", symbol: "chart.xyaxis.line") {
            HStack {
                Picker("Chart", selection: $mode) {
                    ForEach(ChartMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
            }
            switch mode {
            case .power:
                SeriesChart(series: Series.power(samples) + [
                    LineSeries(name: "Mac would use", color: .secondary, dash: LineSeries.Pattern.warning,
                               points: samples.filter(\.isExternalPower).map { ($0.date, $0.demandWatts) }),
                ], unit: "W", height: 220, showsZero: true, strideMinutes: range.stride)
            case .electrical:
                SeriesChart(series: [LineSeries(name: "Voltage", color: Theme.input,
                                                points: samples.map { ($0.date, $0.busVolts) })],
                            unit: "V", height: 120, strideMinutes: range.stride)
                SeriesChart(series: [LineSeries(name: "Current", color: Theme.system,
                                                points: samples.map { ($0.date, $0.busAmps) })],
                            unit: "A", height: 120, strideMinutes: range.stride)
            case .battery:
                SeriesChart(series: [LineSeries(name: "Charge", color: Theme.charging,
                                                points: samples.map { ($0.date, Double($0.percent)) })],
                            unit: "%", height: 120, strideMinutes: range.stride)
                SeriesChart(series: [LineSeries(name: "Temperature", color: Theme.draining,
                                                points: samples.compactMap { s in s.temperatureC.map { (s.date, $0) } })],
                            unit: "°C", height: 120, strideMinutes: range.stride)
            }
            Text("Volts and amps follow the charger input while plugged in and the battery pack on battery. The 24 h and 7 d views use one averaged point per minute, kept for 30 days.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

enum ChartMode: String, CaseIterable, Identifiable {
    case power = "Power", electrical = "Volts and amps", battery = "Charge and heat"
    var id: String { rawValue }
}

enum ChartRange: Int, CaseIterable, Identifiable {
    case five = 5, fifteen = 15, sixty = 60, day = 1440, week = 10080
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .day: return "24 h"
        case .week: return "7 d"
        default: return "\(rawValue) min"
        }
    }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var stride: Int {
        switch self {
        case .five: return 1
        case .fifteen: return 3
        case .sixty: return 10
        case .day: return 180
        case .week: return 1440
        }
    }
    /// Ranges beyond the live hour read the stored minutes.
    var usesArchive: Bool { rawValue > 60 }
}

struct HeroStat: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint == .secondary ? .primary : tint)
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .frame(minWidth: 120, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
    }
}

struct ChargerCard: View {
    let snapshot: PowerSnapshot
    let assessment: ChargerAssessment?
    let quality: ChargerQuality?

    var body: some View {
        Card(title: "Charger", symbol: "powerplug.fill") {
            if let a = snapshot.adapter {
                StatRow(label: "Charger", value: a.title)
                if let m = a.manufacturer { StatRow(label: "Manufacturer", value: m) }
                StatRow(label: "Rated", value: a.ratedWatts.map { "\($0) W" } ?? "n/a")
                StatRow(label: "Negotiated", value: "\(Units.volts(a.negotiatedVolts, digits: 1)) at \(Units.amps(a.negotiatedAmps)) = \(Units.watts(a.ceilingWatts))")
                StatRow(label: "Live input", value: "\(Units.volts(snapshot.inputVolts)) × \(Units.amps(snapshot.inputAmps)) = \(Units.watts(snapshot.inputWatts))")
                if let load = snapshot.chargerLoad {
                    VStack(alignment: .leading, spacing: 4) {
                        StatRow(label: "Load now", value: Units.percent(load), tint: Theme.load(load))
                        LoadBar(fraction: load)
                    }
                }
                if let peak = assessment?.peakLoad {
                    StatRow(label: "Peak load, last 10 min", value: Units.percent(peak), tint: Theme.load(peak))
                }
                if let demand = assessment?.peakDemandWatts {
                    StatRow(label: "Mac would use, peak", value: Units.watts(demand))
                }
                Divider()
                EfficiencyRating(snapshot: snapshot)
                if let quality {
                    Divider()
                    ReportCard(quality: quality)
                }
                if a.isWireless { StatRow(label: "Type", value: "Wireless") }
                if !a.profiles.isEmpty {
                    Divider()
                    Text("Power profiles this charger offers").font(.caption).foregroundStyle(Theme.secondaryText)
                    ProfileTable(adapter: a)
                }
            } else {
                Text("No charger connected. Plug one in to see what it offers and how hard it's working.")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

struct BatteryCard: View {
    let snapshot: PowerSnapshot

    var body: some View {
        let s = snapshot
        Card(title: "Battery", symbol: "battery.75percent") {
            StatRow(label: "Power", value: "\(Units.watts(s.batteryWatts, signed: true))", tint: Theme.battery(s.batteryWatts))
            StatRow(label: "Pack", value: "\(Units.volts(s.batteryVolts)) × \(Units.amps(s.batteryAmps))")
            StatRow(label: "Charge", value: "\(Units.mAh(s.remainingCapacity)) of \(Units.mAh(s.fullChargeCapacity))")
            StatRow(label: "Health", value: "\(Units.percent(s.health, digits: 1)) of \(Units.mAh(s.designCapacity)) design",
                    tint: (s.health ?? 1) < 0.8 ? Theme.warning : nil)
            if let cycles = s.cycleCount {
                StatRow(label: "Cycles", value: s.designCycleCount.map { "\(cycles) of \($0) rated" } ?? "\(cycles)")
            }
            StatRow(label: "Temperature", value: Units.celsius(s.temperatureC),
                    tint: (s.temperatureC ?? 0) >= 40 ? Theme.warning : nil)
            if let watts = s.requestedBatteryWatts {
                StatRow(label: "Battery is asking for",
                        value: "\(Units.watts(watts)) (\(Units.volts(s.requestedCellVolts, digits: 2))/cell, \(Units.amps(s.requestedAmps)))")
            }
            if s.notChargingReason != 0 {
                StatRow(label: "Charging paused", value: "code 0x\(String(s.notChargingReason, radix: 16, uppercase: true))")
            }
            if s.slowChargingReason != 0 {
                StatRow(label: "Slow charging", value: "code 0x\(String(s.slowChargingReason, radix: 16, uppercase: true))")
            }
            if let seconds = s.thermallyLimitedSeconds, seconds > 0 {
                StatRow(label: "Slowed by heat", value: Units.duration(minutes: max(1, seconds / 60)))
            }
            if !s.cellVolts.isEmpty {
                Divider()
                HStack {
                    Text("Cells").font(.caption).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    if let spread = s.cellSpreadMillivolts {
                        Text("Imbalance \(spread) mV")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(spread > 50 ? Theme.warning : .secondary)
                    }
                }
                CellBars(cells: s.cellVolts)
            }
        }
    }
}

struct ChargerHistoryCard: View {
    let chargers: [ChargerRecord]
    let current: String?
    let forget: (String) -> Void

    var body: some View {
        Card(title: "Chargers you've used", symbol: "suitcase.rolling") {
            if chargers.isEmpty {
                Text("Every charger you plug in is remembered here with its peak load, so you can tell which bricks keep up.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Charger"); Text("Limit"); Text("Peak load"); Text("Quality"); Text("Efficiency"); Text("Mac wanted"); Text("Used"); Text("Last seen"); Text("Verdict"); Text("")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    ForEach(chargers) { r in
                        GridRow {
                            HStack(spacing: 6) {
                                if r.fingerprint == current {
                                    Circle().fill(Theme.input).frame(width: 7, height: 7).accessibilityLabel("Connected")
                                }
                                Text(r.title)
                            }
                            Text(Units.watts(r.ceilingWatts, digits: 0))
                            Text(Units.percent(r.peakLoad)).foregroundStyle(Theme.load(r.peakLoad ?? 0))
                            if let g = r.quality {
                                Text(g.title + (r.resistanceOhms.map { String(format: ", %.2f Ω", $0) } ?? ""))
                                    .foregroundStyle(Color(Brand.color(g.tone)))
                            } else {
                                Text("Not graded").foregroundStyle(Theme.secondaryText)
                            }
                            if let e = r.averageEfficiency {
                                let grade = ChargerEfficiency.Grade.of(e)
                                Text("\(Units.percent(e)) \(grade.title)").foregroundStyle(Color(Brand.color(grade.tone)))
                            } else {
                                Text("Not rated").foregroundStyle(Theme.secondaryText)
                            }
                            Text(Units.watts(r.peakDemandWatts, digits: 0))
                            Text(Units.duration(minutes: Int(r.secondsConnected / 60)))
                            Text(r.lastSeen, format: .relative(presentation: .named))
                            Text(r.lastVerdict ?? "Not judged yet").foregroundStyle(Theme.secondaryText)
                            Button {
                                forget(r.fingerprint)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Forget this charger")
                            .accessibilityLabel("Forget \(r.title)")
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }
        }
    }
}

struct AccessoriesCard: View {
    let peripherals: [Peripheral]
    var compact = false

    var body: some View {
        Card(title: "Powering accessories", symbol: "cable.connector") {
            ForEach(peripherals) { p in
                HStack {
                    Label(p.name, systemImage: p.symbolName)
                    Spacer()
                    Text("up to \(Units.watts(p.allocatedWatts))")
                        .monospacedDigit()
                        .foregroundStyle(Theme.system)
                    if !compact {
                        Text("\(p.allocatedMilliamps) mA at 5 V")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 110, alignment: .trailing)
                    }
                }
                .font(.callout)
            }
            Text("macOS reports the power it set aside for each device, not a live reading, so these are ceilings. Whatever they draw is already part of Mac uses.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Charger efficiency as a grade with the wall, delivered and lost watts behind it.
struct EfficiencyRating: View {
    let snapshot: PowerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Efficiency").font(.callout.weight(.semibold))
                Spacer()
                if let e = ChargerEfficiency(snapshot: snapshot) {
                    let tint = Color(Brand.color(e.grade.tone))
                    Text("\(Units.percent(e.efficiency, digits: 1)) · \(e.grade.title)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.15)))
                        .foregroundStyle(tint)
                }
            }
            if let e = ChargerEfficiency(snapshot: snapshot) {
                // The bar is the wall draw; the colored share reached the Mac, the rest is heat
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.input).frame(width: max(4, geo.size.width * e.efficiency - 1))
                        Capsule().fill(Theme.warning.opacity(0.8))
                    }
                }
                .frame(height: 8)
                StatRow(label: "From the wall, est.", value: Units.watts(e.wallWatts))
                StatRow(label: "Delivered to the Mac", value: Units.watts(e.deliveredWatts), tint: Theme.input)
                StatRow(label: "Lost as heat", value: Units.watts(e.lossWatts), tint: Theme.warning)
                Text("Excellent is 94% or more, typical of good GaN chargers; good is 90%, fair 85%. The loss is macOS's own estimate.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(snapshot.isExternalPower
                     ? "Not rated below \(Int(ChargerEfficiency.minimumRatedWatts)) W, where every charger is least efficient."
                     : "Plug in a charger to rate it.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// The charger and cable report card: one row per check, ungraded until measured.
struct ReportCard: View {
    let quality: ChargerQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Report card").font(.callout.weight(.semibold))
                Spacer()
                if let g = quality.overall { GradePill(grade: g) }
            }
            ForEach(quality.checks) { check in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(check.name).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text(check.value).monospacedDigit()
                            .foregroundStyle(check.grade.map { Color(Brand.color($0.tone)) } ?? Theme.secondaryText)
                    }
                    .font(.callout)
                    Text(check.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Text("The overall grade is the weakest check. Cable resistance comes from how voltage falls as current rises, so it separates the cable from the charger.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GradePill: View {
    let grade: ChargerQuality.Grade

    var body: some View {
        let tint = Color(Brand.color(grade.tone))
        Text(grade.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }
}
