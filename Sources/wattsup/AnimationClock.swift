import Foundation
import SwiftUI

/// A fixed point in a looping demo: animations read this time instead of the clock, and round
/// their speeds so every motion completes whole cycles in `loop` seconds and the video loops seamlessly.
struct DemoFrame: Sendable {
    var time: Double
    var loop: Double
}

private struct DemoFrameKey: EnvironmentKey { static let defaultValue: DemoFrame? = nil }

extension EnvironmentValues {
    var demoFrame: DemoFrame? {
        get { self[DemoFrameKey.self] }
        set { self[DemoFrameKey.self] = newValue }
    }
}

/// Accumulates animation phase per key, so a change in speed changes the rate of motion
/// instead of teleporting everything to a new position.
final class AnimationClock {
    private var last: TimeInterval?
    private var phases: [String: Double] = [:]
    private var frameDelta: TimeInterval = 0
    /// Set while rendering a demo; motion then derives from the demo time alone.
    var demo: DemoFrame?

    /// Speed nudged so `period` repeats a whole number of times per loop.
    private func looped(_ speed: Double, period: Double, in demo: DemoFrame) -> Double {
        let cycles = max(1, (speed * demo.loop / period).rounded())
        return cycles * period / demo.loop
    }

    /// Call once per frame before reading phases. Long gaps (paused, hidden) count as one frame.
    func tick(_ now: TimeInterval) {
        defer { last = now }
        guard let last else { frameDelta = 0; return }
        let dt = now - last
        frameDelta = dt > 0 && dt < 0.25 ? dt : 1.0 / 60
    }

    /// Advances and returns the phase for `key`, wrapped to 0..<1 after scaling by `speed`.
    func phase(_ key: String, speed: Double) -> Double {
        if let demo { return (demo.time * looped(speed, period: 1, in: demo)).truncatingRemainder(dividingBy: 1) }
        let next = ((phases[key] ?? 0) + frameDelta * speed).truncatingRemainder(dividingBy: 1)
        phases[key] = next
        return next
    }

    /// Unwrapped accumulated value, for continuous motion such as waves.
    func value(_ key: String, speed: Double, period: Double = 1) -> Double {
        if let demo { return demo.time * looped(speed, period: period, in: demo) }
        let next = (phases[key] ?? 0) + frameDelta * speed
        phases[key] = next
        return next
    }
}
