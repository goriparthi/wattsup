import SwiftUI
import WattsupCore

/// The full detail window: everything the battery controller and charger report.
struct DashboardView: View {
    let monitor: PowerMonitor
    let settings: AppSettings
    @State private var range: ChartRange = .fifteen
    @State private var mode: ChartMode = .power

    var body: some View {
        ScrollView {
            if let s = monitor.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    hero(s)
                    HStack(alignment: .top, spacing: 16) {
                        Card(title: "Power flow", symbol: "arrow.left.arrow.right") {
                            FlowDiagram(snapshot: s, large: true)
                        }
                        Card(title: "Charger check", symbol: "checkmark.shield") {
                            if let a = monitor.assessment { VerdictBanner(assessment: a) }
                        }
                        .frame(width: 360)
                    }
                    charts
                    HStack(alignment: .top, spacing: 16) {
                        ChargerCard(snapshot: s, assessment: monitor.assessment)
                        BatteryCard(snapshot: s)
                    }
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
    }

    private func hero(_ s: PowerSnapshot) -> some View {
        HStack(spacing: 20) {
            ChargeRing(snapshot: s, size: 76, lineWidth: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.percent)%")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(s.statusLine).font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            HeroStat(title: "Charger in", value: s.isExternalPower ? Units.watts(s.inputWatts) : "Unplugged",
                     detail: s.isExternalPower ? "\(Units.volts(s.inputVolts)) · \(Units.amps(s.inputAmps))" : "On battery",
                     tint: s.isExternalPower ? Theme.input : .secondary)
            HeroStat(title: "Mac uses", value: Units.watts(s.systemWatts), detail: "System load", tint: Theme.system)
            HeroStat(title: "Battery", value: Units.watts(s.batteryWatts, signed: true),
                     detail: "\(Units.volts(s.batteryVolts)) · \(Units.amps(s.batteryAmps))",
                     tint: Theme.battery(s.batteryWatts))
            if let wall = s.wallWatts {
                HeroStat(title: "From the wall", value: Units.watts(wall), detail: "Estimated", tint: .secondary)
            }
        }
    }

    private var charts: some View {
        let samples = monitor.history.recent(range.seconds).thinned(to: 400)
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
                .frame(width: 200)
            }
            switch mode {
            case .power:
                SeriesChart(series: Series.power(samples) + [
                    LineSeries(name: "Mac would use", color: .secondary,
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
            Text("Volts and amps follow the charger input while plugged in and the battery pack on battery. History is kept while Wattsup runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum ChartMode: String, CaseIterable, Identifiable {
    case power = "Power", electrical = "Volts and amps", battery = "Charge and heat"
    var id: String { rawValue }
}

enum ChartRange: Int, CaseIterable, Identifiable {
    case five = 5, fifteen = 15, sixty = 60
    var id: Int { rawValue }
    var title: String { "\(rawValue) min" }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var stride: Int { self == .five ? 1 : self == .fifteen ? 3 : 10 }
}

struct HeroStat: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint == .secondary ? .primary : tint)
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 120, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
    }
}

struct ChargerCard: View {
    let snapshot: PowerSnapshot
    let assessment: ChargerAssessment?

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
                if let loss = snapshot.adapterLossWatts, let input = snapshot.inputWatts, input > 0 {
                    StatRow(label: "Conversion loss", value: Units.watts(loss))
                    StatRow(label: "Charger efficiency", value: Units.percent(input / (input + loss), digits: 1))
                }
                if let wall = snapshot.wallWatts { StatRow(label: "From the wall, est.", value: Units.watts(wall)) }
                if a.isWireless { StatRow(label: "Type", value: "Wireless") }
                if !a.profiles.isEmpty {
                    Divider()
                    Text("Power profiles this charger offers").font(.caption).foregroundStyle(.secondary)
                    ProfileTable(adapter: a)
                }
            } else {
                Text("No charger connected. Plug one in to see what it offers and how hard it's working.")
                    .foregroundStyle(.secondary)
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
                    Text("Cells").font(.caption).foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Charger"); Text("Limit"); Text("Peak load"); Text("Mac wanted"); Text("Used"); Text("Last seen"); Text("Verdict"); Text("")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            Text(Units.watts(r.peakDemandWatts, digits: 0))
                            Text(Units.duration(minutes: Int(r.secondsConnected / 60)))
                            Text(r.lastSeen, format: .relative(presentation: .named))
                            Text(r.lastVerdict ?? "Not judged yet").foregroundStyle(.secondary)
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
