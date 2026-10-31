import Foundation

@main struct SamplingCheck {
    static func main() {
        var momentum = ScrollMomentum()
        momentum.sample(x: 0, y: 10, at: 1)
        momentum.sample(x: 0, y: 10, at: 1.02)
        let velocity = momentum.vy
        momentum.sample(x: 0, y: 0, at: 1.02)
        momentum.sample(x: 0, y: 2, at: 1.01)
        precondition(momentum.vy == velocity)
        momentum.end(at: 1.03)
        precondition(momentum.step(seconds: 1 / 120) != nil)
        momentum.reset()
        momentum.sample(x: 0, y: 10, at: 1)
        momentum.sample(x: 0, y: 10, at: 1.02)
        momentum.sample(x: 0, y: 0, at: 1.15)
        momentum.end(at: 1.16)
        precondition(momentum.step(seconds: 1 / 120) == nil)
        var pointer = PointerMotion()
        for i in 0..<120 { _ = pointer.translate(x: 12, y: 0, at: Double(i) / 60) }
        _ = pointer.translate(x: 0, y: 0, at: 119 / 60)
        precondition(pointer.translate(x: 12, y: 0, at: 2).0 == 36)

        func point(_ id: Int, _ x: Double, _ y: Double = 0) -> TouchPoint { TouchPoint(id: id, x: x, y: y) }
        let previous = TouchFrame(time: 0, points: [point(1, 0), point(2, 100)])
        let latest = TouchFrame(time: 0.02, points: [point(1, 20), point(2, 120)])
        let frames = TouchFrameSampler.frames(from: previous, to: latest, trajectories: [
            TouchTrajectory(id: 1, samples: [TouchSample(time: 0.005, x: 5, y: 0), TouchSample(time: 0.015, x: 15, y: 0)]),
            TouchTrajectory(id: 2, samples: [TouchSample(time: 0.01, x: 110, y: 0)])
        ])
        precondition(frames.map(\.time) == [0.005, 0.01, 0.015, 0.02])
        for frame in frames {
            precondition(abs(frame.points[1].x - frame.points[0].x - 100) < 0.00001)
        }
        var commands: [(InputPacket.Kind, Double, Double)] = []
        var engine = GestureEngine(); engine.nativeTransforms = true
        engine.emit = { kind, x, y, _ in commands.append((kind, x, y)) }
        engine.update(previous.points, at: previous.time)
        for frame in frames { engine.update(frame.points, at: frame.time) }
        // Repeating the final UIKit snapshot must not create a zero movement packet.
        engine.update(latest.points, at: latest.time)
        engine.update([], at: 0.03)
        precondition(!commands.contains { $0.0 == .zoom || $0.0 == .rotate || $0.0 == .click })
        let scroll = commands.filter { $0.0 == .scroll }
        precondition(scroll.count == 3 && abs(scroll.reduce(0) { $0 + $1.1 } - 20) < 0.00001)
        precondition(!scroll.contains { $0.1 == 0 && $0.2 == 0 })

        let start = TouchFrame(time: 0, points: [point(1, 0)])
        let end = TouchFrame(time: 0.02, points: [point(1, 20)])
        let curve = TouchFrameSampler.frames(from: start, to: end, trajectories: [TouchTrajectory(id: 1, samples: [
            TouchSample(time: -1, x: -100, y: 0),
            TouchSample(time: 0.01, x: 10, y: 10),
            TouchSample(time: 0.01, x: 10, y: 10),
            TouchSample(time: .nan, x: 100, y: 0),
            TouchSample(time: 0.03, x: 100, y: 0)
        ])])
        precondition(curve.count == 2 && curve[0].points[0] == point(1, 10, 10) && curve.last?.points == end.points)
        commands = []; engine.cancel(); commands = []
        engine.update(start.points, at: 0)
        for frame in curve { engine.update(frame.points, at: frame.time) }
        engine.update([], at: 0.03)
        let moves = commands.filter { $0.0 == .move }
        precondition(moves.count == 2 && moves.reduce(0) { $0 + hypot($1.1, $1.2) } > 25)
        precondition(!commands.contains { $0.0 == .click })
        engine.cancel(); commands = []; engine.threeFingerMode = .drag
        let three = [point(1, 0), point(2, 50), point(3, 100)]
        engine.update(three, at: 3)
        for step in 1...5 {
            engine.update(three.map { point($0.id, $0.x + Double(step * 2)) }, at: 3 + Double(step) / 100)
        }
        engine.update([], at: 3.1)
        precondition(commands.filter { $0.0 == .move }.reduce(0) { $0 + $1.1 } == 10)
        precondition(commands.filter { $0.0 == .down }.count == 1 && commands.filter { $0.0 == .up }.count == 1)
        let changed = TouchFrame(time: 0.02, points: [point(3, 20)])
        precondition(TouchFrameSampler.frames(from: start, to: changed, trajectories: []).count == 1)
        let stale = TouchFrame(time: -1, points: [point(1, -10)])
        precondition(TouchFrameSampler.frames(from: start, to: stale, trajectories: []).isEmpty)
        print("Coalesced curves, synchronized fingers, duplicate/stale samples and flick preservation checks passed")
    }
}
