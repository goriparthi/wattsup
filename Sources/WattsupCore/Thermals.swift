import Foundation

/// Decoding for System Management Controller values. Types are four character codes such as
/// "flt " (little endian float, Apple silicon), "ui8 ", "ui16" (big endian) and "fpe2" (Intel fans).
public enum SMCValue {
    public static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public static func string(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? "????"
    }

    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let v = Double(Float(bitPattern: bits))
            return v.isFinite ? v : nil
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }
}

public struct Fan: Equatable, Sendable, Identifiable {
    public var index: Int
    public var rpm: Double
    public var minRPM: Double?
    public var maxRPM: Double?
    public var id: Int { index }

    public init(index: Int, rpm: Double, minRPM: Double?, maxRPM: Double?) {
        self.index = index
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    public func name(of count: Int) -> String {
        count == 2 ? (index == 0 ? "Left fan" : "Right fan") : count == 1 ? "Fan" : "Fan \(index + 1)"
    }

    /// Share of the fan's range in use, or nil without a known range.
    public var fraction: Double? {
        guard let lo = minRPM, let hi = maxRPM, hi > lo else { return nil }
        return min(1, max(0, (rpm - lo) / (hi - lo)))
    }
}

/// Fans and chip temperatures at one instant.
public struct Thermals: Equatable, Sendable {
    public var fans: [Fan]
    public var cpuC: Double?
    public var cpuHottestC: Double?
    public var gpuC: Double?

    public init(fans: [Fan], cpuC: Double?, cpuHottestC: Double?, gpuC: Double?) {
        self.fans = fans
        self.cpuC = cpuC
        self.cpuHottestC = cpuHottestC
        self.gpuC = gpuC
    }

    public var fanRPM: Double? { fans.isEmpty ? nil : fans.map(\.rpm).max() }

    /// Builds the summary from raw sensor readings keyed by SMC key. CPU sensors start with
    /// Tp or Te (performance and efficiency cores), GPU with Tg; implausible values are dropped.
    public static func summarize(fans: [Fan], temperatures: [String: Double]) -> Thermals {
        let plausible = temperatures.filter { $0.value > 5 && $0.value < 130 }
        let cpu = plausible.filter { $0.key.hasPrefix("Tp") || $0.key.hasPrefix("Te") }.map(\.value)
        let gpu = plausible.filter { $0.key.hasPrefix("Tg") }.map(\.value)
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return Thermals(fans: fans, cpuC: mean(cpu), cpuHottestC: cpu.max(), gpuC: mean(gpu))
    }

    /// The SMC keys worth reading: CPU and GPU die sensors.
    public static func isChipSensor(_ key: String) -> Bool {
        key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("Tg")
    }
}
