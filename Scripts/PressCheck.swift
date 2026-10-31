import Foundation

@main struct PressCheck {
    static func main() {
        var events: [InputPacket.Kind] = []
        var engine = GestureEngine()
        engine.emit = { kind, _, _, _ in events.append(kind) }
        func point(_ pressure: Double?, x: Double = 0) -> [TouchPoint] { [TouchPoint(id: 1, x: x, y: 0, pressure: pressure)] }
        engine.update(point(0.1), at: 0)
        engine.update(point(0.6), at: 0.1)
        engine.update(point(0.5), at: 0.12)
        engine.update(point(0.7, x: 12), at: 0.2)
        engine.update(point(0.3, x: 12), at: 0.3)
        engine.update([], at: 0.4)
        precondition(events == [.contact, .down, .move, .up])

        engine.cancel(); events = []
        engine.update(point(0.7), at: 1)
        engine.update(point(0.3), at: 1.1)
        engine.update(point(0.7), at: 1.2)
        engine.update([], at: 1.25)
        precondition(events == [.contact, .down, .up, .down, .up])

        engine.cancel(); events = []
        engine.holdToClick = true; engine.tapToClick = false
        engine.update(point(nil), at: 2)
        precondition(engine.needsClock)
        engine.advance(at: 2.34); precondition(events == [.contact])
        engine.advance(at: 2.36); engine.advance(at: 2.5)
        engine.update(point(nil, x: 15), at: 2.6)
        engine.update([], at: 2.7)
        precondition(events == [.contact, .down, .move, .up] && !engine.needsClock)

        engine.cancel(); events = []
        engine.update(point(0.1), at: 3); engine.advance(at: 4)
        precondition(events == [.contact], "Light pressure is not a long-press fallback")
        engine.cancel(); events = []
        engine.update(point(nil), at: 5); engine.update(point(nil, x: 20), at: 5.1); engine.advance(at: 6)
        precondition(!events.contains(.down), "Normal movement became a held click")

        engine.cancel(); events = []
        engine.update(point(0.7), at: 7); engine.cancel()
        precondition(events == [.contact, .down, .reset] && !engine.needsClock)
        events = []
        engine.update(point(0.7), at: 8)
        engine.update([TouchPoint(id: 1, x: 0, y: 0, pressure: 0.7), TouchPoint(id: 2, x: 50, y: 0)], at: 8.1)
        engine.update([], at: 8.2)
        precondition(events.filter { $0 == .down }.count == 1 && events.filter { $0 == .up }.count == 1 && !events.contains(.click))

        // Pressure peaks inside coalesced samples must survive even with no positional movement.
        engine.cancel(); events = []
        let first = TouchFrame(time: 9, points: point(0.1))
        engine.update(first.points, at: first.time)
        let frames = TouchFrameSampler.frames(from: first, to: TouchFrame(time: 9.02, points: point(0.2)), trajectories: [TouchTrajectory(id: 1, samples: [TouchSample(time: 9.01, x: 0, y: 0, pressure: 0.7)])])
        for frame in frames { engine.update(frame.points, at: frame.time) }
        engine.update([], at: 9.03)
        precondition(events == [.contact, .down, .up])
        print("Pressure hysteresis, repress, drag, hold fallback, cancellation and coalesced peaks passed")
    }
}
