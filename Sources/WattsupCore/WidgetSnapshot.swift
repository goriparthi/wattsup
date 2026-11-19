import Foundation

/// The small reading the menu bar app hands to the widget. The widget is sandboxed, so the app
/// writes this into the widget's own container, which needs no shared entitlement.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var percent: Int
    public var status: String
    public var charging: Bool
    public var onCharger: Bool
    public var inputWatts: Double?
    public var macWatts: Double
    public var batteryWatts: Double
    public var charger: String?
    public var verdict: String?

    public init(_ s: PowerSnapshot, verdict: String?) {
        date = s.date
        percent = s.percent
        status = s.statusLine
        charging = s.state == .charging
        onCharger = s.isExternalPower
        inputWatts = s.inputWatts
        macWatts = s.systemWatts
        batteryWatts = s.batteryWatts
        charger = s.adapter?.title
        self.verdict = verdict
    }

    /// Worth pushing to the widget: anything a glance would notice.
    public func differsMeaningfully(from other: WidgetSnapshot?) -> Bool {
        guard let other else { return true }
        return percent != other.percent || onCharger != other.onCharger || charging != other.charging
            || verdict != other.verdict || abs(macWatts - other.macWatts) >= 2
            || date.timeIntervalSince(other.date) >= 300
    }

    public static let widgetBundleID = "com.goriparthi.wattsup.widget"
    public static let fileName = "widget.json"

    /// Where the app writes: inside the widget's container, addressed from the user's home.
    public static func containerURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/Wattsup/\(fileName)")
    }

    /// Where the widget reads: its own Application Support, which is the same file from inside.
    public static var widgetLocalURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Wattsup/\(fileName)")
    }

    public func encoded() -> Data? {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return try? e.encode(self)
    }

    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(WidgetSnapshot.self, from: data)
    }
}
