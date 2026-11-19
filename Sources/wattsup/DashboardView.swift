import Charts
import SwiftUI
import WattsupCore

/// The full detail window: everything the battery controller and charger report.
struct DashboardView: View {
    let monitor: PowerMonitor
    let settings: AppSettings
    let visibility: MenuBarVisibility
    /// Rendering to an image needs the content without its scroll view
    var rendering = false
    /// Only the hero row, power flow and charger check, for the site's animated loop
    var marketing = false
    @State private var range: ChartRange = .fifteen
    @State private var mode: ChartMode = .power

    var body: some View {
        if rendering { content.background(Theme.canvas).environment(\.themeStyle, Theme.Style(large: true)) } else {
            ScrollView { content }
                .environment(\.themeStyle, Theme.Style(large: true))
                .frame(minWidth: 900, minHeight: 640)
                .background(Theme.canvas)
                .tint(Theme.accent)
                .onAppear { monitor.impact.viewerAppeared() }
                .onDisappear { monitor.impact.viewerDisappeared() }
        }
    }

    @ViewBuilder private var content: some View {
            if marketing, let s = monitor.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    hero(s)
                    HStack(alignment: .top, spacing: 16) {
                        Card(title: "Power flow", symbol: "arrow.left.arrow.right") {
                            Spacer(minLength: 0)
                            PowerFlowView(snapshot: s, large: true)
                            Spacer(minLength: 0)
                        }
                        Card(title: "Charger check", symbol: "checkmark.shield") {
                            if let a = monitor.assessment { VerdictBanner(assessment: a) }
                        }
                        .frame(width: 360)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            } else if let s = monitor.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    if visibility.hidden {
                        Label {
                            Text("macOS is hiding the Wattsup readout because the menu bar is full or the notch covers it. Command drag a few items out of the menu bar to make room.")
                        } icon: {
                            Image(systemName: "eye.slash")
                        }
                        .font(Theme.Style(large: true).body)
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
                                    .font(Theme.Style(large: true).caption)
                                    .foregroundStyle(Theme.Style(large: true).secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !s.peripherals.isEmpty || !monitor.accessories.devices.isEmpty {
                                AccessoriesCard(peripherals: s.peripherals, batteries: monitor.accessories.devices, compact: true)
                            }
                        }
                        .frame(width: 360)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 16) {
                        ChargerCard(snapshot: s, assessment: monitor.assessment, quality: monitor.quality)
                        BatteryCard(snapshot: s, trend: HealthTrend(points: monitor.healthPoints))
                        if let t = s.thermals { ThermalsCard(thermals: t, batteryC: s.temperatureC) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    charts
                    HStack(alignment: .top, spacing: 16) {
                        EnergyCard(days: EnergyAccount.daily(monitor.archive), price: settings.pricePerKWh)
                        EnergyByAppCard(impact: monitor.impact)
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

    private func hero(_ s: PowerSnapshot) -> some View {
        HStack(spacing: 20) {
            BatteryTank(snapshot: s, width: 54, height: 86)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.percent)%")
                    .font(.system(size: 36, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 8) {
                    Text(s.statusLine).font(.title3).foregroundStyle(Theme.Style(large: true).secondary)
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
                .frame(maxWidth: 520)
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
            case .thermals:
                SeriesChart(series: [LineSeries(name: "Chip", color: Theme.warning, dash: LineSeries.Pattern.warning,
                                                points: samples.compactMap { s in s.cpuTempC.map { (s.date, $0) } })],
                            unit: "°C", height: 120, strideMinutes: range.stride)
                SeriesChart(series: [LineSeries(name: "Fans", color: Theme.system, dash: LineSeries.Pattern.system,
                                                points: samples.compactMap { s in s.fanRPM.map { (s.date, $0) } })],
                            unit: "rpm", height: 120, strideMinutes: range.stride)
            case .battery:
                SeriesChart(series: [LineSeries(name: "Charge", color: Theme.charging,
                                                points: samples.map { ($0.date, Double($0.percent)) })],
                            unit: "%", height: 120, strideMinutes: range.stride)
                SeriesChart(series: [LineSeries(name: "Temperature", color: Theme.draining,
                                                points: samples.compactMap { s in s.temperatureC.map { (s.date, $0) } })],
                            unit: "°C", height: 120, strideMinutes: range.stride)
            }
            Text("Volts and amps follow the charger input while plugged in and the battery pack on battery. The 24 h and 7 d views use one averaged point per minute, kept for 30 days.")
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
        }
    }
}

enum ChartMode: String, CaseIterable, Identifiable {
    case power = "Power", electrical = "Volts and amps", battery = "Charge and heat", thermals = "Thermals"
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
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint == .secondary ? .primary : tint)
            Text(detail).font(Theme.Style(large: true).caption.monospacedDigit()).foregroundStyle(Theme.Style(large: true).secondary)
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
                    Text("Power profiles this charger offers").font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary)
                    ProfileTable(adapter: a)
                }
            } else {
                Text("No charger connected. Plug one in to see what it offers and how hard it's working.")
                    .foregroundStyle(Theme.Style(large: true).secondary)
            }
        }
    }
}

struct BatteryCard: View {
    let snapshot: PowerSnapshot
    let trend: HealthTrend

    var body: some View {
        let s = snapshot
        Card(title: "Battery", symbol: "battery.75percent") {
            StatRow(label: "Power", value: "\(Units.watts(s.batteryWatts, signed: true))", tint: Theme.battery(s.batteryWatts))
            StatRow(label: "Pack", value: "\(Units.volts(s.batteryVolts)) × \(Units.amps(s.batteryAmps))")
            StatRow(label: "Charge", value: "\(Units.mAh(s.remainingCapacity)) of \(Units.mAh(s.fullChargeCapacity))")
            StatRow(label: "Health", value: "\(Units.percent(s.health, digits: 1)) of \(Units.mAh(s.designCapacity)) design",
                    tint: (s.health ?? 1) < 0.8 ? Theme.warning : nil)
            if let full = s.fullEnergyWh, let design = s.designEnergyWh {
                StatRow(label: "Capacity", value: String(format: "about %.0f Wh of %.0f Wh design", full, design))
            }
            if let left = s.remainingEnergyWh {
                StatRow(label: "Stored now", value: String(format: "about %.0f Wh", left)
                        + (s.runtimeHoursAtCurrentDraw.map { ", \(Units.duration(minutes: Int($0 * 60))) at \(Units.watts(s.systemWatts, digits: 0))" } ?? ""))
            }
            if let cycles = s.cycleCount {
                StatRow(label: "Cycles", value: s.designCycleCount.map { "\(cycles) of \($0) rated" } ?? "\(cycles)")
            }
            StatRow(label: "Temperature", value: Units.celsius(s.temperatureC),
                    tint: (s.temperatureC ?? 0) >= 40 ? Theme.warning : nil)
            if let watts = s.requestedBatteryWatts {
                StatRow(label: "Battery is asking for",
                        value: "\(Units.watts(watts)) (\(Units.volts(s.requestedCellVolts, digits: 2))/cell, \(Units.amps(s.requestedAmps)))")
            }
            if let hold = ChargeHold(snapshot: s) {
                VStack(alignment: .leading, spacing: 4) {
                    StatRow(label: "Charging", value: hold.title, tint: hold.title == "Full" ? nil : Theme.warning)
                    Text(hold.detail + (hold.code.map { " macOS reason code 0x\(String($0, radix: 16, uppercase: true))." } ?? ""))
                        .font(Theme.Style(large: true).caption)
                        .foregroundStyle(Theme.Style(large: true).secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if hold.title != "Full" {
                        Button("Open Battery Settings", action: SystemSettings.openBattery).controlSize(.small)
                    }
                }
            }
            if s.slowChargingReason != 0 {
                StatRow(label: "Slow charging", value: "code 0x\(String(s.slowChargingReason, radix: 16, uppercase: true))")
            }
            if let seconds = s.thermallyLimitedSeconds, seconds > 0 {
                StatRow(label: "Slowed by heat", value: Units.duration(minutes: max(1, seconds / 60)))
            }
            Divider()
            HealthTrendView(trend: trend)
            if let life = s.lifetime {
                Divider()
                Text("Lifetime, as the battery recorded it").font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary)
                if let a = life.maxDischargeAmps {
                    StatRow(label: "Highest draw", value: Units.amps(a) + (s.peakDischargeWatts.map { String(format: ", about %.0f W", $0) } ?? ""))
                }
                if let a = life.maxChargeAmps { StatRow(label: "Highest charge current", value: Units.amps(a)) }
                if let lo = life.minTempC, let hi = life.maxTempC {
                    StatRow(label: "Temperature range", value: String(format: "%.0f to %.0f °C", lo, hi)
                            + (life.averageTempC.map { String(format: ", average %.1f", $0) } ?? ""))
                }
                if let h = life.operatingHours { StatRow(label: "Operating time", value: "\(h.formatted()) hours") }
            }
            if !s.cellVolts.isEmpty {
                Divider()
                HStack {
                    Text("Cells").font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary)
                    Spacer()
                    if let spread = s.cellSpreadMillivolts {
                        Text("Imbalance \(spread) mV")
                            .font(Theme.Style(large: true).caption.monospacedDigit())
                            .foregroundStyle(spread > 50 ? Theme.warning : .secondary)
                    }
                }
                CellPack(cells: s.cellVolts, charging: s.state == .charging)
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
                    .foregroundStyle(Theme.Style(large: true).secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Charger"); Text("Limit"); Text("Peak load"); Text("Quality"); Text("Efficiency"); Text("Mac wanted"); Text("Used"); Text("Last seen"); Text("Verdict"); Text("")
                    }
                    .font(Theme.Style(large: true).caption)
                    .foregroundStyle(Theme.Style(large: true).secondary)
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
                                Text("Not graded").foregroundStyle(Theme.Style(large: true).secondary)
                            }
                            if let e = r.averageEfficiency {
                                let grade = ChargerEfficiency.Grade.of(e)
                                Text("\(Units.percent(e)) \(grade.title)").foregroundStyle(Color(Brand.color(grade.tone)))
                            } else {
                                Text("Not rated").foregroundStyle(Theme.Style(large: true).secondary)
                            }
                            Text(Units.watts(r.peakDemandWatts, digits: 0))
                            Text(Units.duration(minutes: Int(r.secondsConnected / 60)))
                            Text(r.lastSeen, format: .relative(presentation: .named))
                            Text(r.lastVerdict ?? "Not judged yet").foregroundStyle(Theme.Style(large: true).secondary)
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
    var batteries: [AccessoryBattery] = []
    var compact = false

    var body: some View {
        Card(title: "Accessories", symbol: "cable.connector") {
            ForEach(batteries) { d in
                HStack {
                    Label(d.name, systemImage: d.symbolName).lineLimit(1)
                    Spacer()
                    Text(d.summary).monospacedDigit()
                        .foregroundStyle((d.lowest ?? 100) <= 20 ? Theme.warning : Theme.secondaryText)
                }
                .font(Theme.Style(large: true).body)
            }
            ForEach(peripherals) { p in
                HStack {
                    Label(p.name, systemImage: p.symbolName)
                    Spacer()
                    Text("up to \(Units.watts(p.allocatedWatts))")
                        .monospacedDigit()
                        .foregroundStyle(Theme.system)
                    if !compact {
                        Text("\(p.allocatedMilliamps) mA at 5 V")
                            .font(Theme.Style(large: true).caption.monospacedDigit())
                            .foregroundStyle(Theme.Style(large: true).secondary)
                            .frame(width: 110, alignment: .trailing)
                    }
                }
                .font(Theme.Style(large: true).body)
            }
            if !peripherals.isEmpty {
                Text("Powered over USB: macOS reports the power it set aside for each device, not a live reading, so these are ceilings. Whatever they draw is already part of Mac uses.")
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
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
                    .font(Theme.Style(large: true).caption)
                    .foregroundStyle(Theme.Style(large: true).secondary)
            } else {
                Text(snapshot.isExternalPower
                     ? "Not rated below \(Int(ChargerEfficiency.minimumRatedWatts)) W, where every charger is least efficient."
                     : "Plug in a charger to rate it.")
                    .font(Theme.Style(large: true).caption)
                    .foregroundStyle(Theme.Style(large: true).secondary)
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
                        Text(check.name).foregroundStyle(Theme.Style(large: true).secondary)
                        Spacer()
                        Text(check.value).monospacedDigit()
                            .foregroundStyle(check.grade.map { Color(Brand.color($0.tone)) } ?? Theme.secondaryText)
                    }
                    .font(Theme.Style(large: true).body)
                    Text(check.detail).font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary)
                }
            }
            Text("The overall grade is the weakest check. Cable resistance comes from how voltage falls as current rises, so it separates the cable from the charger.")
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
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

/// Fans and chip temperatures from the SMC, next to the power that drives them.
struct ThermalsCard: View {
    let thermals: Thermals
    let batteryC: Double?

    var body: some View {
        Card(title: "Thermals", symbol: "fan") {
            ForEach(thermals.fans) { fan in
                HStack(spacing: 10) {
                    SpinningFan(rpm: fan.rpm)
                    VStack(alignment: .leading, spacing: 4) {
                        StatRow(label: fan.name(of: thermals.fans.count),
                                value: fan.rpm < 50 ? "Off" : "\(Int(fan.rpm.rounded()).formatted()) rpm")
                        if fan.rpm >= 50, let f = fan.fraction { LoadBar(fraction: f, height: 6) }
                    }
                }
            }
            if thermals.fans.isEmpty {
                StatRow(label: "Fans", value: "None, this Mac is fanless")
            }
            StatRow(label: "CPU", value: thermals.cpuC.map { Units.celsius($0) } ?? "n/a",
                    tint: (thermals.cpuHottestC ?? 0) >= 95 ? Theme.warning : nil)
            if let hottest = thermals.cpuHottestC { StatRow(label: "Hottest core", value: Units.celsius(hottest)) }
            if let gpu = thermals.gpuC { StatRow(label: "GPU", value: Units.celsius(gpu)) }
            StatRow(label: "Battery", value: Units.celsius(batteryC))
            Text("Read from the System Management Controller. More watts means more heat, and the fans follow a few seconds later.")
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The apps doing the most work right now, by Activity Monitor's energy impact score.
struct EnergyByAppCard: View {
    let impact: EnergyImpactMonitor

    var body: some View {
        Card(title: "Energy use by app", symbol: "chart.bar.xaxis") {
            if impact.apps.isEmpty {
                Text("Sampling…").foregroundStyle(Theme.Style(large: true).secondary)
            } else {
                let top = impact.apps.first?.impact ?? 1
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(impact.apps) { app in
                        HStack(spacing: 8) {
                            if let path = app.bundlePath {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "gearshape").frame(width: 18, height: 18).foregroundStyle(Theme.Style(large: true).secondary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(app.name).lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.1f", app.impact)).monospacedDigit().foregroundStyle(Theme.Style(large: true).secondary)
                                }
                                .font(Theme.Style(large: true).body)
                                LoadBarTinted(fraction: app.impact / max(top, 1), tint: Theme.system)
                            }
                        }
                    }
                }
            }
            Text("Energy impact as Activity Monitor scores it: a relative measure of how hard each app works the Mac, not watts. Helpers count toward their app.")
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Watt hours per day from the stored minutes, with an optional cost at the user's price.
struct EnergyCard: View {
    let days: [DayEnergy]
    let price: Double

    var body: some View {
        let week = Array(days.suffix(7))
        let month = EnergyAccount.total(days)
        let today = days.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0 : nil }
        Card(title: "Energy", symbol: "bolt.batteryblock") {
            HStack(alignment: .top, spacing: 24) {
                figure("Today from the wall", today.map { EnergyAccount.format(wattHours: $0.wallWh) } ?? "0 Wh")
                figure("Mac used today", today.map { EnergyAccount.format(wattHours: $0.macWh) } ?? "0 Wh")
                figure("Last 30 days", EnergyAccount.format(wattHours: month.wallWh),
                       detail: price > 0 ? month.cost(perKWh: price).map { $0.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")) } : nil)
            }
            if week.count > 1 {
                Chart(week) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Wh", d.wallWh))
                        .foregroundStyle(Theme.input)
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                .frame(height: 110)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Energy from the wall per day: " + week.map {
                    "\($0.day.formatted(.dateTime.weekday(.wide))) \(EnergyAccount.format(wattHours: $0.wallWh))"
                }.joined(separator: ", "))
            }
            Text("From the wall per day, integrated from one averaged reading per minute. Days without Wattsup running are not counted.")
                .font(Theme.Style(large: true).caption)
                .foregroundStyle(Theme.Style(large: true).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func figure(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let detail { Text(detail).font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary) }
        }
    }
}

/// Battery wear over months: the stored daily health, its rate, and when it would reach 80%.
struct HealthTrendView: View {
    let trend: HealthTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health over time").font(Theme.Style(large: true).caption).foregroundStyle(Theme.Style(large: true).secondary)
            if trend.points.count > 1 {
                Chart(trend.points) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Health", p.health * 100))
                        .foregroundStyle(Theme.charging)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 70)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery health over time, from \(Units.percent(trend.points.first?.health, digits: 1)) to \(Units.percent(trend.points.last?.health, digits: 1))")
            }
            if trend.isCollecting {
                Text("Collecting daily readings. A wear rate appears after two weeks, a projection once there is a clear trend.")
                    .font(Theme.Style(large: true).caption)
                    .foregroundStyle(Theme.Style(large: true).secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let m = trend.perMonth { StatRow(label: "Wear per month", value: String(format: "%.2f points", m * 100)) }
                if let c = trend.perHundredCycles { StatRow(label: "Wear per 100 cycles", value: String(format: "%.2f points", c * 100)) }
                StatRow(label: "Reaches 80%",
                        value: trend.monthsToService.map { $0 < 1 ? "within a month" : "in about \(Int($0.rounded())) months" } ?? "No decline yet")
            }
        }
    }
}
