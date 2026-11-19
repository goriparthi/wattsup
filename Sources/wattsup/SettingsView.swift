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
                List {
                    ForEach(settings.metrics) { metric in
                        MetricRow(metric: metric, snapshot: monitor.snapshot, on: true) { settings.toggle(metric) }
                    }
                    .onMove { settings.move(from: $0, to: $1) }
                }
                .frame(minHeight: CGFloat(max(1, settings.metrics.count)) * 30)
                ForEach(MenuBarMetric.allCases.filter { !settings.metrics.contains($0) }) { metric in
                    MetricRow(metric: metric, snapshot: monitor.snapshot, on: false) { settings.toggle(metric) }
                }
            } header: {
                Text("Readings")
            } footer: {
                HStack {
                    Text("Drag shown readings to reorder. In the stacked layout the first half goes on the top row.")
                    Spacer()
                    Button("Reset") { settings.resetMenuBar() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { settings.launchesAtLogin },
                                                      set: { settings.setLaunchesAtLogin($0) }))
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(Theme.warning)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: Binding(get: { settings.checksForUpdates },
                                                                        set: { settings.checksForUpdates = $0 }))
                HStack {
                    Text(updates.status).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { Task { await updates.check(interactive: true) } }
                        .disabled(updates.busy)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("A daily look at github.com/goriparthi/wattsup for a newer release. It is the only network request Wattsup makes, and updates install only if Apple notarized them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("No reading yet").foregroundStyle(.secondary)
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
    let toggle: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { on }, set: { _ in toggle() })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.title)
                    if !metric.help.isEmpty {
                        Text(metric.help).font(.caption).foregroundStyle(.secondary)
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
            if on {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
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
        _ = (settings.metrics, settings.layout, settings.usesColors, settings.icon, settings.outlined)
        if let button = button as? NSStatusBarButton {
            StatusItemRenderer.apply(to: button, snapshot: snapshot, settings: settings)
        }
    }
}
