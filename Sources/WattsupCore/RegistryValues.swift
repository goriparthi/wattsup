import Foundation

// Typed reads over the AppleSmartBattery property dictionary. Values arrive as NSNumber,
// and signed fields are sometimes stored as unsigned bit patterns, hence `signed`.
extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        (self[key] as? NSNumber).map { Int($0.int64Value) }
    }

    func signed(_ key: String) -> Int? {
        (self[key] as? NSNumber).map { Int(Int32(truncatingIfNeeded: $0.int64Value)) }
    }

    func bool(_ key: String) -> Bool? {
        (self[key] as? NSNumber)?.boolValue
    }

    func string(_ key: String) -> String? {
        guard let value = self[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func dicts(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }

    func ints(_ key: String) -> [Int] {
        (self[key] as? [NSNumber])?.map { Int($0.int64Value) } ?? []
    }

    /// Milli-units (mV, mA, mW) to base units.
    func milli(_ key: String, signed isSigned: Bool = false) -> Double? {
        (isSigned ? signed(key) : int(key)).map { Double($0) / 1000 }
    }
}
