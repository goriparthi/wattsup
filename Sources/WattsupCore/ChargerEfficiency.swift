import Foundation

/// How much of the wall power the charger delivers, graded. Light loads are not rated
/// because every charger is least efficient near idle, which would grade it unfairly.
public struct ChargerEfficiency: Equatable, Sendable {
    public enum Grade: String, Equatable, Sendable {
        case excellent, good, fair, poor

        public var title: String { rawValue.capitalized }

        public var tone: MetricTone {
            switch self {
            case .excellent, .good: return .charging
            case .fair: return .draining
            case .poor: return .warning
            }
        }

        public static func of(_ efficiency: Double) -> Grade {
            efficiency >= 0.94 ? .excellent : efficiency >= 0.90 ? .good : efficiency >= 0.85 ? .fair : .poor
        }
    }

    public static let minimumRatedWatts = 10.0

    public var efficiency: Double
    public var lossWatts: Double
    public var deliveredWatts: Double
    public var wallWatts: Double { deliveredWatts + lossWatts }
    public var grade: Grade { Grade.of(efficiency) }

    /// Nil on battery, without a loss figure, or below the load worth rating.
    public init?(snapshot s: PowerSnapshot) {
        guard s.isExternalPower, let input = s.inputWatts, let loss = s.adapterLossWatts,
              input >= Self.minimumRatedWatts, loss >= 0 else { return nil }
        deliveredWatts = input
        lossWatts = loss
        efficiency = input / (input + loss)
    }

    public var summary: String {
        "\(Units.percent(efficiency)) \(grade.title), \(Units.watts(lossWatts)) lost as heat"
    }
}
