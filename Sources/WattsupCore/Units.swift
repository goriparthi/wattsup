import Foundation

/// Display formatting shared by the menu bar, popover, dashboard and CLI.
public enum Units {
    /// The true minus sign U+2212, which the brand uses for draining power.
    public static let minus = "\u{2212}"

    public static func watts(_ w: Double?, signed: Bool = false, digits: Int = 1) -> String {
        guard let w else { return "n/a" }
        let value = abs(w) < 0.05 ? 0 : w
        let sign = value > 0 && signed ? "+" : value < 0 ? minus : ""
        return sign + String(format: "%.\(digits)f W", abs(value))
    }

    /// Rounds to `digits` and clears the sign on zero, so a reading never shows "-0.0".
    public static func clean(_ v: Double, digits: Int = 1) -> Double {
        let scale = pow(10, Double(digits))
        let r = (v * scale).rounded() / scale
        return r == 0 ? 0 : r
    }

    public static func volts(_ v: Double?, digits: Int = 2) -> String {
        guard let v else { return "n/a" }
        return String(format: "%.\(digits)f V", v)
    }

    public static func amps(_ a: Double?, digits: Int = 2) -> String {
        guard let a else { return "n/a" }
        let value = abs(a) < 0.005 ? 0 : a
        return (value < 0 ? minus : "") + String(format: "%.\(digits)f A", abs(value))
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

    /// A precise local time that still reads naturally: "Today 4:12 PM", "Yesterday 1:54 PM",
    /// "Tue, Nov 18, 9:03 AM", with the year added once it is not this year. Display only.
    public static func seen(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        let time = DateFormatter()
        time.calendar = calendar; time.timeZone = calendar.timeZone; time.locale = locale
        time.dateStyle = .none; time.timeStyle = .short
        let clock = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(clock)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "Yesterday \(clock)"
        }
        let day = DateFormatter()
        day.calendar = calendar; day.timeZone = calendar.timeZone; day.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        day.setLocalizedDateFormatFromTemplate(sameYear ? "EEEMMMd" : "EEEMMMdyyyy")
        return "\(day.string(from: date)), \(clock)"
    }

    /// Compact form for the menu bar, e.g. "1:05".
    public static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func profile(_ p: PDProfile) -> String {
        String(format: "%g V  %.2g A  %.0f W", p.volts, p.amps, p.watts)
    }
}
