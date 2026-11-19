// Desktop and Notification Center widget. It renders the reading the menu bar app writes into
// this extension's container, and never reads hardware or opens a socket itself.
import SwiftUI
import WattsupCore
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func read() -> WidgetSnapshot? {
        guard let url = WidgetSnapshot.widgetLocalURL, let data = try? Data(contentsOf: url) else { return nil }
        return WidgetSnapshot.decode(data)
    }

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: read()) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: read()))
    }

    // The app asks for a reload when something changes; this is only the fallback cadence
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date(), snapshot: read())], policy: .after(Date().addingTimeInterval(600))))
    }
}

struct WattsupWidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(s.percent)%").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    Spacer()
                    Image(systemName: s.charging ? "bolt.fill" : s.onCharger ? "powerplug.fill" : "battery.75percent")
                        .foregroundStyle(.secondary)
                }
                Text(s.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if family == .systemSmall {
                    row("Charger", s.onCharger ? watts(s.inputWatts) : "Unplugged")
                    row("Mac", watts(s.macWatts))
                    row("Battery", signed(s.batteryWatts))
                } else {
                    HStack(spacing: 6) {
                        stat("Charger", s.onCharger ? watts(s.inputWatts) : "Unplugged")
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        stat("Mac", watts(s.macWatts))
                        Image(systemName: s.batteryWatts < 0 ? "chevron.left" : "chevron.right").foregroundStyle(.tertiary)
                        stat("Battery", signed(s.batteryWatts))
                    }
                    if let verdict = s.verdict {
                        Text(verdict).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Text("Open Wattsup to start readings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func watts(_ w: Double?) -> String { w.map { String(format: "%.1f W", $0) } ?? "n/a" }
    private func signed(_ w: Double) -> String {
        abs(w) < 0.05 ? "0.0 W" : (w > 0 ? "+" : "\u{2212}") + String(format: "%.1f W", abs(w))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct WattsupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WattsupWidget", provider: Provider()) { entry in
            WattsupWidgetView(entry: entry)
        }
        .configurationDisplayName("Wattsup")
        .description("Battery, charger and Mac power at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
