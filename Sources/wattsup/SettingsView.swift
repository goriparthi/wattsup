import AppKit
import SwiftUI
import WattsupCore

/// Menu bar customization with a live preview, plus general and update preferences.
struct SettingsView: View {
    let monitor: PowerMonitor
    let settings: AppSettings
    let updates: UpdateController

    var body: some View {
        Form {
            Section("Menu bar") {
                preview
                Picker("Layout", selection: Binding(get: { settings.layout }, set: { settings.layout = $0 })) {
                    ForEach(MenuBarLayout.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Color readings by meaning", isOn: Binding(get: { settings.usesColors }, set: { settings.usesColors = $0 }))
                Toggle("Outline the readout", isOn: Binding(get: { settings.outlined }, set: { settings.outlined = $0 }))
                Picker("Icon", selection: Binding(get: { settings.icon }, set: { settings.icon = $0 })) {
                    ForEach(MenuBarIcon.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                ForEach(Array(settings.order.enumerated()), id: \.element) { index, metric in
                    MetricRow(metric: metric, snapshot: monitor.snapshot, on: settings.shown.contains(metric),
                              canMoveUp: index > 0, canMoveDown: index < settings.order.count - 1,
                              move: { settings.shift(metric, by: $0) }) { settings.toggle(metric) }
                }
            } header: {
                Text("Readings")
            } footer: {
                HStack {
                    Text("Use the arrows to reorder. Left to right in the menu bar; stacked puts the first half on top.")
                    Spacer()
                    Button("Reset") { settings.resetMenuBar() }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
            Section {
                HStack {
                    Text("macOS battery icon")
                    Spacer()
                    Button("Open Menu Bar Settings…", action: SystemSettings.openMenuBar)
                }
            } header: {
                Text("Menu bar space")
            } footer: {
                Text("Wattsup can show battery percent and time, so the built in battery icon is optional. Turn off Battery in that list, or Command drag the icon out of the menu bar.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Section {
                ForEach(AlertKind.allCases) { kind in
                    HStack {
                        Toggle(kind.title, isOn: Binding(
                            get: { settings.alerts.contains(kind) },
                            set: { on in if on { settings.alerts.insert(kind) } else { settings.alerts.remove(kind) } }))
                        if kind == .chargedTo {
                            Spacer()
                            Stepper("\(settings.chargedAlertLevel)%", value: Binding(
                                get: { settings.chargedAlertLevel }, set: { settings.chargedAlertLevel = $0 }),
                                    in: 50...100, step: 5)
                                .fixedSize()
                                .disabled(!settings.alerts.contains(kind))
                        }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Each alert fires once when the situation starts, then waits at least 30 minutes before repeating.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Section {
                HStack {
                    Text("Electricity price")
                    Spacer()
                    TextField("0.00", value: Binding(get: { settings.pricePerKWh }, set: { settings.pricePerKWh = max(0, $0) }),
                              format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("\(Locale.current.currency?.identifier ?? "") per kWh").foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Energy cost")
            } footer: {
                Text("Optional. Used only to estimate the cost of what your charger draws from the wall.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { settings.launchesAtLogin },
                                                      set: { settings.setLaunchesAtLogin($0) }))
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(Theme.warning)
                }
            }
            Section {
                Toggle("Check for updates daily", isOn: Binding(get: { settings.checksForUpdates },
                                                                        set: { settings.checksForUpdates = $0 }))
                HStack {
                    Text(updates.status).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Check Now") { Task { await updates.check(interactive: true) } }
                        .disabled(updates.busy)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("A daily look at github.com/goriparthi/wattsup for a newer release. It is the only network request Wattsup makes, and updates install only if Apple notarized them.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 560)
    }

    /// A dark strip standing in for the menu bar, drawn by the same renderer.
    private var preview: some View {
        HStack {
            Spacer()
            if let s = monitor.snapshot {
                MenuBarPreview(snapshot: s, settings: settings)
            } else {
                Text("No reading yet").foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.85)))
        .environment(\.colorScheme, .dark)
    }
}

struct MetricRow: View {
    let metric: MenuBarMetric
    let snapshot: PowerSnapshot?
    let on: Bool
    var canMoveUp = false
    var canMoveDown = false
    var move: (Int) -> Void = { _ in }
    let toggle: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { on }, set: { _ in toggle() })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.title)
                    if !metric.help.isEmpty {
                        Text(metric.help).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            if let s = snapshot {
                Text(metric.text(for: s) ?? "n/a")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color(nsColor: StatusItemRenderer.color(metric.tone(for: s), colored: true)))
            }
            ControlGroup {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .accessibilityLabel("Move \(metric.title) earlier")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .accessibilityLabel("Move \(metric.title) later")
            }
            .controlSize(.small)
            .fixedSize()
        }
    }
}

struct MenuBarPreview: NSViewRepresentable {
    let snapshot: PowerSnapshot
    let settings: AppSettings

    func makeNSView(context: Context) -> NSButton {
        let button = NSStatusBarButton()
        button.isBordered = false
        button.appearance = NSAppearance(named: .darkAqua)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        // Touch every setting so SwiftUI redraws the preview when any of them changes
        _ = (settings.order, settings.shown, settings.layout, settings.usesColors, settings.icon, settings.outlined)
        if let button = button as? NSStatusBarButton {
            StatusItemRenderer.apply(to: button, snapshot: snapshot, settings: settings)
        }
    }
}
