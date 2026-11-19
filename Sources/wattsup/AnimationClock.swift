import Foundation

/// Accumulates animation phase per key, so a change in speed changes the rate of motion
/// instead of teleporting everything to a new position.
final class AnimationClock {
    private var last: TimeInterval?
    private var phases: [String: Double] = [:]
    private var frameDelta: TimeInterval = 0

    /// Call once per frame before reading phases. Long gaps (paused, hidden) count as one frame.
    func tick(_ now: TimeInterval) {
        defer { last = now }
        guard let last else { frameDelta = 0; return }
        let dt = now - last
        frameDelta = dt > 0 && dt < 0.25 ? dt : 1.0 / 60
    }

    /// Advances and returns the phase for `key`, wrapped to 0..<1 after scaling by `speed`.
    func phase(_ key: String, speed: Double) -> Double {
        let next = ((phases[key] ?? 0) + frameDelta * speed).truncatingRemainder(dividingBy: 1)
        phases[key] = next
        return next
    }

    /// Unwrapped accumulated value, for continuous motion such as waves.
    func value(_ key: String, speed: Double) -> Double {
        let next = (phases[key] ?? 0) + frameDelta * speed
        phases[key] = next
        return next
    }
}
