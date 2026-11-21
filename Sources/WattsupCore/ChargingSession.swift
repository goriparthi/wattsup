import Foundation

/// A receipt for one stretch on a charger: from plugging in to unplugging.
public struct ChargingSession: Codable, Equatable, Sendable, Identifiable {
    public var start: Date
    public var end: Date
    public var charger: String
    public var chargerTitle: String
    public var startPercent: Int
    public var endPercent: Int
    /// Energy that went into the battery and that came from the wall, in watt hours
    public var batteryWh: Double
    public var wallWh: Double
    public var peakInputWatts: Double
    /// Seconds the charger check said the charger was the bottleneck or could not keep up
    public var limitedSeconds: Double
    /// Minutes from plugging in to reaching 80%, when the session started below it
    public var minutesTo80: Double?
    public var id: Date { start }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var averageInputWatts: Double { duration > 0 ? wallWh / (duration / 3600) : 0 }
    public var limitedShare: Double { duration > 0 ? min(1, limitedSeconds / duration) : 0 }

    public var summary: String {
        var s = "\(startPercent)% to \(endPercent)% in \(Units.duration(minutes: max(1, Int(duration / 60))))"
        s += String(format: ", %.0f Wh in, peak %.0f W", batteryWh, peakInputWatts)
        if limitedShare >= 0.5 { s += ", charger limited most of the time" }
        return s
    }
}

/// Builds sessions from readings. Gaps over a minute, such as sleep, are not counted as charging.
public struct SessionTracker: Sendable {
    private var open: ChargingSession?
    private var last: PowerSnapshot?
    public static let minimumSeconds: TimeInterval = 120

    public init() {}

    /// Feeds one reading; returns a finished session when the charger is unplugged or changed.
    public mutating func update(_ s: PowerSnapshot, limited: Bool) -> ChargingSession? {
        defer { last = s }
        var finished: ChargingSession?
        let fp = s.isExternalPower ? s.adapter?.fingerprint : nil
        if let current = open, fp != current.charger {
            finished = current.duration >= Self.minimumSeconds ? current : nil
            open = nil
        }
        guard let fp, let adapter = s.adapter else { return finished }
        if open == nil {
            open = ChargingSession(start: s.date, end: s.date, charger: fp, chargerTitle: adapter.title,
                                   startPercent: s.percent, endPercent: s.percent, batteryWh: 0, wallWh: 0,
                                   peakInputWatts: s.inputWatts ?? 0, limitedSeconds: 0, minutesTo80: nil)
            return finished
        }
        guard var session = open, let previous = last else { return finished }
        let dt = s.date.timeIntervalSince(previous.date)
        if dt > 0 && dt <= 60 {
            session.batteryWh += max(0, s.batteryWatts) * dt / 3600
            session.wallWh += (s.wallWatts ?? s.inputWatts ?? 0) * dt / 3600
            if limited { session.limitedSeconds += dt }
        }
        session.end = s.date
        session.endPercent = s.percent
        session.peakInputWatts = max(session.peakInputWatts, s.inputWatts ?? 0)
        if session.minutesTo80 == nil, session.startPercent < 80, s.percent >= 80 {
            session.minutesTo80 = s.date.timeIntervalSince(session.start) / 60
        }
        open = session
        return finished
    }

    /// The session in progress, for saving on quit.
    public var current: ChargingSession? {
        guard let open, open.duration >= Self.minimumSeconds else { return nil }
        return open
    }
}
