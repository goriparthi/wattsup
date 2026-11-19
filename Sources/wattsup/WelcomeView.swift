import SwiftUI
import WattsupCore

/// First run: pick a readout, make room in the menu bar, choose login and alerts. Shown once.
struct WelcomeView: View {
    let settings: AppSettings
    let done: () -> Void

    enum Preset: String, CaseIterable, Identifiable {
        case standard = "Charger and Mac", electrical = "Watts, volts and amps", battery = "Battery"
        var id: String { rawValue }
        var metrics: [MenuBarMetric] {
            switch self {
            case .standard: return MenuBarMetric.defaults
            case .electrical: return [.watts, .volts, .amps]
            case .battery: return [.percent, .time, .health]
            }
        }
    }

    @State private var preset: Preset = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Wattsup").font(.title2.weight(.semibold))
                    Text("Live power for your Mac, in the menu bar.").foregroundStyle(Theme.secondaryText)
                }
            }
            step(1, "Choose what the menu bar shows") {
                Picker("Readout", selection: $preset) {
                    ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: preset) { _, new in settings.metrics = new.metrics }
                Text("You can pick from \(MenuBarMetric.allCases.count) readings and reorder them any time in Settings.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            step(2, "Make room in the menu bar") {
                Text("Wattsup shows battery percent and time, so the built in battery icon is optional. Turning it off leaves more space, which matters on Macs with a notch.")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Menu Bar Settings", action: SystemSettings.openMenuBar)
            }
            step(3, "Options") {
                Toggle("Open Wattsup at login", isOn: Binding(get: { settings.launchesAtLogin },
                                                               set: { settings.setLaunchesAtLogin($0) }))
                Toggle("Notify me about charger problems and a hot battery", isOn: Binding(
                    get: { !settings.alerts.isEmpty },
                    set: { settings.alerts = $0 ? Set(AlertKind.allCases.filter(\.enabledByDefault)) : [] }))
            }
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.callout.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent.opacity(0.18)))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }
}
