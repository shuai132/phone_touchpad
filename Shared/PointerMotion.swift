import Foundation

/// Maps touch points to cursor points without depending on network packet arrival frequency.
struct PointerMotion {
    var sensitivity = 1.0
    var acceleration = true
    private var lastTime: Double?
    private var filteredSpeed = 0.0
    private var scale: Double {
        let factor = min(max((filteredSpeed - 35) / 650, 0), 1)
        let gain = acceleration ? 0.65 + factor * 2.35 : 1.5
        let sensitivity = self.sensitivity.isFinite ? min(max(self.sensitivity, 0.25), 3) : 1
        return sensitivity * gain
    }
    mutating func reset() { lastTime = nil; filteredSpeed = 0 }
    mutating func translate(x: Double, y: Double, at time: Double) -> (Double, Double) {
        guard x.isFinite, y.isFinite, time.isFinite else { return (0, 0) }
        if x == 0 && y == 0 { return (0, 0) }
        let elapsed = time - (lastTime ?? (time - 1 / 60))
        guard elapsed > 0 else { return (x * scale, y * scale) }
        lastTime = time
        let dt = elapsed > 0 && elapsed < 0.1 ? max(elapsed, 1 / 240) : 1 / 60
        if elapsed >= 0.1 { filteredSpeed = 0 }
        let speed = hypot(x, y) / dt
        let mix = 1 - exp(-dt * 30)
        filteredSpeed += (speed - filteredSpeed) * mix
        return (x * scale, y * scale)
    }
}
