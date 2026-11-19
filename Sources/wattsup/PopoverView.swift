import AppKit
import SwiftUI
import WattsupCore

/// The quick look shown from the menu bar; the dashboard holds the full detail.
struct PopoverActions {
    var openDashboard: () -> Void
    var openSettings: () -> Void
    var openWelcome: () -> Void
    var checkForUpdates: () -> Void
}

struct PopoverView: View {
    let monitor: PowerMonitor
    let settings: AppSettings
    let actions: PopoverActions

    var body: some View {
        // Scrolls only when taller than the screen allows, so small displays never clip the top
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical) { content }
        }
        .frame(width: 360)
        .frame(maxHeight: Self.maxHeight)
        .onAppear { monitor.impact.viewerAppeared() }
        .onDisappear { monitor.impact.viewerDisappeared() }
    }

    private static var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 40
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = monitor.snapshot {
                header(s)
                PowerFlowView(snapshot: s)
                if let a = monitor.assessment { VerdictBanner(assessment: a, showsAdvisories: false) }
                SeriesChart(series: Series.power(monitor.history.recent(300).thinned(to: 150)),
                            unit: "W", height: 90, showsZero: true, showsLegend: false)
                details(s)
            } else {
                UnavailableView(availability: monitor.availability)
            }
            Divider()
            footer
        }
        .padding(14)
    }

    private func header(_ s: PowerSnapshot) -> some View {
        HStack(spacing: 12) {
            BatteryTank(snapshot: s, width: 34, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.percent)%")
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(s.statusLine).font(.callout).foregroundStyle(Theme.secondaryText)
                    EnergyModeBadge(mode: s.energyMode)
                }
            }
            Spacer()
        }
    }

    /// Readings grouped by what they describe, so charger and battery figures never blur together.
    private func details(_ s: PowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let adapter = s.adapter {
                DetailGroup(title: "Charger", symbol: "powerplug.fill") {
                    StatRow(label: "Charger", value: adapter.title)
                    if let e = ChargerEfficiency(snapshot: s) {
                        StatRow(label: "Efficiency", value: e.summary, tint: Color(Brand.color(e.grade.tone)))
                    }
                    if let q = monitor.quality, let g = q.overall {
                        StatRow(label: "Quality", value: g.title + (q.resistanceOhms.map { String(format: ", cable %.2f Ω", $0) } ?? ""),
                                tint: Color(Brand.color(g.tone)))
                    }
                    if let load = s.chargerLoad {
                        StatRow(label: "Load", value: "\(Units.percent(load)) of \(Units.watts(adapter.ceilingWatts, digits: 0))",
                                tint: Theme.load(load))
                    }
                }
                Divider()
            }
            DetailGroup(title: "Battery", symbol: "battery.75percent") {
                if let hold = ChargeHold(snapshot: s), hold.title != "Full" {
                    StatRow(label: "Charging", value: hold.title, tint: Theme.warning)
                }
                StatRow(label: "Health", value: Units.percent(s.health, digits: 1))
                StatRow(label: "Temperature", value: Units.celsius(s.temperatureC))
            }
            Divider()
            DetailGroup(title: "Mac", symbol: "laptopcomputer") {
                if let t = s.thermals {
                    if !t.fans.isEmpty {
                        StatRow(label: "Fans", value: t.fans.allSatisfy { $0.rpm < 50 } ? "Off"
                                : t.fans.map { "\(Int($0.rpm.rounded()).formatted())" }.joined(separator: " / ") + " rpm")
                    }
                    if let c = t.cpuC { StatRow(label: "Chip", value: Units.celsius(c)) }
                }
                ForEach(monitor.accessories.devices) { d in
                    StatRow(label: d.name, value: d.summary, tint: (d.lowest ?? 100) <= 20 ? Theme.warning : nil)
                }
                if let busiest = monitor.impact.apps.first {
                    StatRow(label: "Busiest app", value: busiest.name)
                }
                if !s.peripherals.isEmpty {
                    StatRow(label: "Powering", value: s.peripherals.map(\.name).joined(separator: ", ")
                            + ", up to " + Units.watts(s.peripherals.allocatedWatts, digits: 0), tint: Theme.system)
                }
                EnergyModePicker(energy: monitor.energy, source: s.isExternalPower ? .charger : .battery, compact: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Dashboard", action: actions.openDashboard)
                .keyboardShortcut("d")
            Spacer()
            SettingsMenu(settings: settings, actions: actions)
        }
    }
}

struct SettingsMenu: View {
    let settings: AppSettings
    let actions: PopoverActions

    var body: some View {
        Menu {
            Section("Show in menu bar") {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(metric.title, isOn: Binding(
                        get: { settings.metrics.contains(metric) },
                        set: { _ in settings.toggle(metric) }))
                }
            }
            Divider()
            Button("Settings…", action: actions.openSettings)
                .keyboardShortcut(",")
            Button("Check for Updates…", action: actions.checkForUpdates)
            Toggle("Check for Updates Daily", isOn: Binding(
                get: { settings.checksForUpdates }, set: { settings.checksForUpdates = $0 }))
            Button("Battery Settings…", action: SystemSettings.openBattery)
            Button("Show Welcome…", action: actions.openWelcome)
            Button("Reveal Logs in Finder", action: Diagnostics.revealInFinder)
            Divider()
            Button("Quit Wattsup") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Settings")
    }
}

struct UnavailableView: View {
    let availability: PowerMonitor.Availability

    var body: some View {
        switch availability {
        case .loading, .ready:
            ProgressView().frame(maxWidth: .infinity)
        case .noBattery:
            ContentUnavailableView("No battery found", systemImage: "battery.0percent",
                                   description: Text("Wattsup reads a MacBook's battery and charger. This Mac has no battery."))
        case .readFailed(let message):
            ContentUnavailableView("Can't read the battery", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        }
    }
}

private struct DetailGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(title).foregroundStyle(.primary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.secondaryText)
            }
            .font(.subheadline.weight(.semibold))
            content
        }
    }
}
