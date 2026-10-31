import Foundation

/// Velocity is in screen points per second. Integrates exponential friction using real elapsed time.
struct ScrollMomentum {
    private(set) var vx = 0.0
    private(set) var vy = 0.0
    private var previousTime: Double?
    private var lastSample: Double?
    mutating func sample(x: Double, y: Double, at time: Double) {
        guard x.isFinite, y.isFinite, time.isFinite, x != 0 || y != 0 else { return }
        guard let previousTime else { self.previousTime = time; lastSample = time; return }
        let dt = time - previousTime
        // Duplicate and stale samples must not erase the last actual movement velocity.
        guard dt > 0 else { return }
        self.previousTime = time; lastSample = time
        guard dt < 0.1 else { vx = 0; vy = 0; return }
        let decay = exp(-dt * 25)
        let rate = -expm1(-dt * 25) / dt
        vx = vx * decay + x * rate
        vy = vy * decay + y * rate
    }
    mutating func end(at time: Double) {
        if time - (lastSample ?? 0) > 0.08 { vx = 0; vy = 0 }
        previousTime = nil
    }
    mutating func step(seconds: Double) -> (Double, Double)? {
        guard seconds > 0, seconds < 0.1, hypot(vx, vy) > 8 else { vx = 0; vy = 0; return nil }
        let decay = exp(-seconds * 7)
        let dx = vx * (1 - decay) / 7, dy = vy * (1 - decay) / 7
        vx *= decay; vy *= decay
        return (dx, dy)
    }
    mutating func reset() { self = ScrollMomentum() }
}
