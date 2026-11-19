import Foundation

/// Display formatting shared by the menu bar, popover, dashboard and CLI.
public enum Units {
    public static func watts(_ w: Double?, signed: Bool = false, digits: Int = 1) -> String {
        guard let w else { return "n/a" }
        let sign = signed && w > 0.05 ? "+" : ""
        return sign + String(format: "%.\(digits)f W", abs(w) < 0.05 ? 0 : w)
    }

    public static func volts(_ v: Double?, digits: Int = 2) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.\(digits)f V", v)
    }

    public static func amps(_ a: Double?, digits: Int = 2) -> String {
        guard let a else { return "n/a" }
        return String(format: "%.\(digits)f A", abs(a) < 0.005 ? 0 : a)
    }

    public static func percent(_ fraction: Double?, digits: Int = 0) -> String {
        guard let fraction else { return "n/a" }
        return String(format: "%.\(digits)f%%", fraction * 100)
    }

    public static func celsius(_ c: Double?) -> String {
        guard let c else { return "n/a" }
        return String(format: "%.1f °C", c)
    }

    public static func mAh(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return "\(value.formatted()) mAh"
    }

    public static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Compact form for the menu bar, e.g. "1:05".
    public static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func profile(_ p: PDProfile) -> String {
        String(format: "%g V  %.2g A  %.0f W", p.volts, p.amps, p.watts)
    }
}
