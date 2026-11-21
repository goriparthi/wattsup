import Foundation

public enum AlertKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case cantKeepUp, cableCapped, batteryHot, chargedTo, unpluggedLow, chargingReceipt
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cantKeepUp: return "Charger can't keep up"
        case .cableCapped: return "Cable is limiting power"
        case .batteryHot: return "Battery is hot"
        case .chargedTo: return "Charged to a level"
        case .unpluggedLow: return "Unplugged at low battery"
        case .chargingReceipt: return "Charging receipt when you unplug"
        }
    }

    public var enabledByDefault: Bool { self != .chargedTo && self != .chargingReceipt }
}

public struct AlertEvent: Equatable, Sendable {
    public var kind: AlertKind
    public var title: String
    public var body: String
}

/// Turns readings into notifications. Each alert fires on a transition, then waits to re-arm
/// and observes a cooldown, so a reading hovering at a threshold never nags.
public struct AlertEngine: Sendable {
    public var enabled: Set<AlertKind>
    public var chargedLevel: Int
    public static let cooldown: TimeInterval = 30 * 60
    static let hot = 40.0, coolAgain = 37.0, lowBattery = 20

    private var lastFired: [AlertKind: Date] = [:]
    private var armed: Set<AlertKind> = Set(AlertKind.allCases)
    private var previous: PowerSnapshot?
    private var previousVerdict: ChargerAssessment.Verdict?
    private var previousHeadline: String?

    public init(enabled: Set<AlertKind>, chargedLevel: Int) {
        self.enabled = enabled
        self.chargedLevel = chargedLevel
    }

    public mutating func evaluate(_ s: PowerSnapshot, assessment a: ChargerAssessment?) -> [AlertEvent] {
        defer { previous = s; previousVerdict = a?.verdict; previousHeadline = a?.headline }
        guard let old = previous else { return [] }
        var out: [AlertEvent] = []

        if let a, a.verdict == .notKeepingUp, previousVerdict != .notKeepingUp {
            fire(.cantKeepUp, "Charger can't keep up", a.detail, at: s.date, into: &out)
        }
        let cableNow = a.map { $0.headline.lowercased().contains("cable") } ?? false
        let cableBefore = previousHeadline?.lowercased().contains("cable") ?? false
        if cableNow, !cableBefore, let a {
            fire(.cableCapped, a.headline, a.detail, at: s.date, into: &out)
        }

        if let t = s.temperatureC {
            if t >= Self.hot && armed.contains(.batteryHot) {
                // Disarm only when it actually fired, so a cooldown never swallows the next one
                if fire(.batteryHot, "Battery is hot", String(format: "The battery is at %.0f °C. Heat wears it faster; give the Mac some air or a break.", t), at: s.date, into: &out) {
                    armed.remove(.batteryHot)
                }
            } else if t < Self.coolAgain {
                armed.insert(.batteryHot)
            }
        }

        if s.state == .charging, s.percent >= chargedLevel, old.percent < chargedLevel, armed.contains(.chargedTo) {
            if fire(.chargedTo, "Charged to \(chargedLevel)%", "Your battery reached \(s.percent)%.", at: s.date, into: &out) {
                armed.remove(.chargedTo)
            }
        } else if s.percent <= chargedLevel - 5 {
            armed.insert(.chargedTo)
        }

        if old.isExternalPower, !s.isExternalPower, s.percent <= Self.lowBattery {
            fire(.unpluggedLow, "Unplugged at \(s.percent)%",
                 "The charger was disconnected with little charge left.", at: s.date, into: &out)
        }
        return out
    }

    @discardableResult
    private mutating func fire(_ kind: AlertKind, _ title: String, _ body: String, at now: Date, into out: inout [AlertEvent]) -> Bool {
        guard enabled.contains(kind) else { return false }
        if let last = lastFired[kind], now.timeIntervalSince(last) < Self.cooldown { return false }
        lastFired[kind] = now
        out.append(AlertEvent(kind: kind, title: title, body: body))
        return true
    }
}
