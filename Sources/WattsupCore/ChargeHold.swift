import Foundation

/// Explains why a Mac on a charger is not charging. macOS does not expose its charge limit
/// or Optimized Charging state, so the wording names likely causes rather than claiming one.
public struct ChargeHold: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var code: Int?

    public init?(snapshot s: PowerSnapshot) {
        guard s.isExternalPower, s.state == .held || s.state == .full || (s.notChargingReason != 0 && s.state != .charging) else {
            return nil
        }
        code = s.notChargingReason == 0 ? nil : s.notChargingReason
        if s.percent >= 99 || s.state == .full {
            title = "Full"
            detail = "The battery is full, so the Mac runs from the charger. macOS tops it up now and then."
        } else if (75...85).contains(s.percent) {
            title = "Held at \(s.percent)%"
            detail = "Usually Optimized Battery Charging, which finishes charging just before you normally unplug, "
                + "or a charge limit set in Battery settings. Both reduce battery wear."
        } else {
            title = "Charging paused at \(s.percent)%"
            detail = "macOS has paused charging. Common reasons are a charge limit, Optimized Battery Charging, "
                + "or heat. The Mac keeps running from the charger meanwhile."
        }
    }
}
