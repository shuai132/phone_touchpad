import Foundation

@main struct GestureCheck {
    static func main() {
        var output: [(InputPacket.Kind, Double, Double, Int)] = []
        var engine = GestureEngine()
        engine.emit = { output.append(($0, $1, $2, $3)) }
        func point(_ id: Int, _ x: Double, _ y: Double = 0) -> TouchPoint { TouchPoint(id: id, x: x, y: y) }
        engine.update([], at: 0)
        precondition(output.isEmpty)
        engine.update([point(1, 0)], at: 0)
        engine.update([], at: 0.1)
        precondition(output.filter { $0.0 == .click }.count == 1)
        output = []
        engine.update([point(1, 0)], at: 1)
        engine.update([point(1, 0), point(2, 20)], at: 1.02)
        engine.update([point(1, 20), point(2, 40)], at: 1.04)
        engine.update([point(1, 20)], at: 1.06)
        engine.update([point(1, 40)], at: 1.08)
        engine.update([], at: 1.1)
        precondition(output.filter { $0.0 == .scrollBegin }.count == 1)
        precondition(output.filter { $0.0 == .scrollEnd }.count == 1)
        precondition(!output.contains { $0.0 == .move || $0.0 == .click })
        output = []
        // Equal centroid does not make opposing finger movement into a tap.
        engine.update([point(1, 0), point(2, 20)], at: 2)
        engine.update([point(1, -20), point(2, 40)], at: 2.05)
        engine.update([], at: 2.1)
        precondition(!output.contains { $0.0 == .click })
        output = []
        engine.threeFingerMode = .drag
        engine.update([point(1, 0), point(2, 20), point(3, 40)], at: 3)
        engine.update([point(1, 20), point(2, 40), point(3, 60)], at: 3.1)
        engine.update([point(1, 20), point(2, 40)], at: 3.2)
        engine.cancel()
        precondition(output.filter { $0.0 == .down }.count == 1)
        precondition(output.filter { $0.0 == .up }.count == 1)
        precondition(output.contains { $0.0 == .move && $0.3 == 3 })
        precondition(!output.contains { $0.0 == .click || $0.0 == .swipe })
        output = []
        engine.threeFingerMode = .swipe
        engine.update([point(1, 0), point(2, 20), point(3, 40)], at: 4)
        engine.update([point(1, 80), point(2, 100), point(3, 120)], at: 4.1)
        engine.update([point(1, 100), point(2, 120), point(3, 140)], at: 4.2)
        engine.update([], at: 4.3)
        precondition(output.filter { $0.0 == .swipe }.count == 1)
        var momentum = ScrollMomentum()
        momentum.sample(x: 0, y: 10, at: 10)
        momentum.sample(x: 0, y: 10, at: 10.016)
        momentum.end(at: 10.02)
        var last = Double.infinity
        var count = 0
        while let (_, y) = momentum.step(seconds: 1 / 120) {
            precondition(y > 0 && y < last)
            last = y; count += 1
            precondition(count < 2000)
        }
        precondition(count > 1)
        momentum.sample(x: 0, y: 10, at: 20)
        momentum.sample(x: 0, y: 10, at: 20.016)
        momentum.end(at: 21)
        precondition(momentum.step(seconds: 1 / 120) == nil)
        var slow = PointerMotion(), fast = PointerMotion()
        var slowGain = 0.0, fastGain = 0.0
        for i in 0..<60 {
            slowGain = slow.translate(x: 0.2, y: 0, at: Double(i) / 60).0 / 0.2
            fastGain = fast.translate(x: 12, y: 0, at: Double(i) / 60).0 / 12
        }
        precondition(fastGain > slowGain * 2)
        var linear = PointerMotion()
        linear.acceleration = false; linear.sensitivity = 2
        let linearResult = linear.translate(x: 3, y: -4, at: 1)
        precondition(linearResult.0 == 9 && linearResult.1 == -12)
        let invalid = linear.translate(x: .nan, y: 0, at: 2)
        precondition(invalid.0 == 0 && invalid.1 == 0)
        fast.reset()
        let restarted = fast.translate(x: 0.2, y: 0, at: 100).0
        precondition(restarted < 0.2)
        print("Gesture, momentum and pointer checks passed")
    }
}
