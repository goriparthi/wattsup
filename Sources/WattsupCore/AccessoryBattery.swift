import Foundation

/// A wireless accessory's battery, from the Bluetooth profile (AirPods and similar report
/// left, right and case) or the HID registry (keyboards, mice, trackpads).
public struct AccessoryBattery: Equatable, Sendable, Identifiable {
    public struct Level: Equatable, Sendable {
        public var label: String?
        public var percent: Int
    }

    public var name: String
    public var kind: String?
    public var levels: [Level]
    public var id: String { name }

    public var lowest: Int? { levels.map(\.percent).min() }

    public var summary: String {
        levels.map { ($0.label.map { "\($0) " } ?? "") + "\($0.percent)%" }.joined(separator: ", ")
    }

    public var symbolName: String {
        let n = (name + " " + (kind ?? "")).lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods") { return "airpodspro" }
        if n.contains("headphone") || n.contains("beats") { return "headphones" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("mouse") { return "magicmouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        return "dot.radiowaves.left.and.right"
    }

    /// Connected devices with a battery level in `system_profiler SPBluetoothDataType -json`.
    public static func parse(bluetoothJSON data: Data) -> [AccessoryBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        let labels = [("device_batteryLevelLeft", "Left"), ("device_batteryLevelRight", "Right"),
                      ("device_batteryLevelCase", "Case"), ("device_batteryLevelMain", nil),
                      ("device_batteryLevel", nil)] as [(String, String?)]
        var out: [AccessoryBattery] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let levels = labels.compactMap { key, label -> Level? in
                        guard let text = info[key] as? String,
                              let p = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
                        return Level(label: label, percent: p)
                    }
                    if !levels.isEmpty {
                        out.append(AccessoryBattery(name: name, kind: info["device_minorType"] as? String, levels: levels))
                    }
                }
            }
        }
        return out
    }

    /// One HID device entry with a BatteryPercent, such as a Magic Keyboard or Mouse.
    public init?(hid d: [String: Any]) {
        guard let name = d["Product"] as? String, let p = (d["BatteryPercent"] as? NSNumber)?.intValue,
              (0...100).contains(p), !name.lowercased().contains("internal") else { return nil }
        self.init(name: name, kind: nil, levels: [Level(label: nil, percent: p)])
    }

    public init(name: String, kind: String?, levels: [Level]) {
        self.name = name
        self.kind = kind
        self.levels = levels
    }
}
