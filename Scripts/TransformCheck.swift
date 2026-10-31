import Foundation

@main struct TransformCheck {
    static func main() {
        var events: [(InputPacket.Kind, Double)] = []
        var engine = GestureEngine()
        engine.nativeTransforms = true
        engine.emit = { kind, x, _, _ in events.append((kind, x)) }
        func pair(length: Double = 100, angle: Double = 0, x: Double = 0) -> [TouchPoint] {
            let dx = cos(angle) * length / 2, dy = sin(angle) * length / 2
            return [TouchPoint(id: 1, x: x - dx, y: -dy), TouchPoint(id: 2, x: x + dx, y: dy)]
        }
        engine.update(pair(), at: 0)
        engine.update(pair(length: 110).reversed(), at: 0.02)
        engine.update(pair(length: 121), at: 0.04)
        engine.update([], at: 0.06)
        let zoom = events.filter { $0.0 == .zoom }.map(\.1)
        precondition(zoom.count == 2 && abs((1 + zoom[0]) * (1 + zoom[1]) - 1.21) < 0.00001)
        precondition(events.filter { $0.0 == .zoomBegin }.count == 1 && events.filter { $0.0 == .zoomEnd }.count == 1)
        precondition(!events.contains { [.scroll, .click, .rotate].contains($0.0) })
        engine.cancel(); events = []
        engine.update(pair(angle: 3.1), at: 1)
        engine.update(pair(angle: -3.0), at: 1.02)
        engine.update(pair(length: 110, angle: -2.9), at: 1.04)
        engine.update([], at: 1.06)
        let rotation = events.filter { $0.0 == .rotate }.reduce(0) { $0 + $1.1 }
        precondition(abs(rotation + (2 * .pi - 6.0) * 180 / .pi) < 0.001)
        precondition(events.contains { $0.0 == .zoom } && events.contains { $0.0 == .rotateEnd })
        precondition(!events.contains { $0.0 == .scroll || $0.0 == .click })
        engine.cancel(); events = []
        engine.update(pair(), at: 2)
        engine.update(pair(x: 7), at: 2.02)
        engine.update(pair(x: 14), at: 2.04)
        engine.update([], at: 2.06)
        precondition(events.filter { $0.0 == .scroll }.reduce(0) { $0 + $1.1 } == 14)
        precondition(!events.contains { $0.0 == .zoom || $0.0 == .rotate || $0.0 == .click })
        engine.cancel(); events = []
        engine.update(pair(), at: 3)
        engine.update(pair(length: 120), at: 3.02)
        engine.cancel()
        precondition(events.last?.0 == .reset && !events.contains { $0.0 == .zoomEnd })
        engine.nativeTransforms = false; events = []
        engine.update(pair(), at: 4)
        engine.update(pair(length: 120), at: 4.02)
        engine.update([], at: 4.04)
        precondition(!events.contains { $0.0 == .zoom || $0.0 == .click || $0.0 == .scroll })
        print("Pinch, simultaneous rotation, angle wrap, scroll arbitration and cancellation checks passed")
    }
}
