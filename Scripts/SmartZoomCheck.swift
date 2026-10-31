import Foundation

@main struct SmartZoomCheck {
    static func main() {
        var events: [InputPacket.Kind] = []
        var engine = GestureEngine()
        engine.nativeTransforms = true
        engine.emit = { kind, _, _, _ in events.append(kind) }
        func pair(_ x: Double = 0) -> [TouchPoint] { [TouchPoint(id: 1, x: x, y: 0), TouchPoint(id: 2, x: x + 100, y: 0)] }
        engine.update(pair(), at: 0); engine.update([], at: 0.05)
        precondition(engine.needsClock && !events.contains(.click))
        engine.advance(at: 0.34)
        precondition(events.filter { $0 == .click }.count == 1 && !engine.needsClock)
        engine.cancel(); events = []
        engine.update(pair(), at: 1); engine.update([], at: 1.05)
        engine.update(pair(), at: 1.15); engine.update([], at: 1.2); engine.advance(at: 1.5)
        precondition(events.filter { $0 == .smartZoom }.count == 1 && !events.contains(.click))
        engine.cancel(); events = []
        engine.update(pair(), at: 1.6); engine.update([], at: 1.65)
        engine.update(pair(), at: 1.85); engine.advance(at: 1.95)
        engine.update([], at: 2.0)
        precondition(events.filter { $0 == .smartZoom }.count == 1 && !events.contains(.click))
        engine.cancel(); events = []
        engine.update(pair(), at: 2.1); engine.update([], at: 2.15)
        engine.update(pair(100), at: 2.25); engine.update([], at: 2.3); engine.advance(at: 2.6)
        precondition(events.filter { $0 == .click }.count == 2 && !events.contains(.smartZoom))
        engine.cancel(); events = []
        engine.update(pair(), at: 3); engine.update([], at: 3.05); engine.cancel(); engine.advance(at: 3.5)
        precondition(!events.contains(.click) && !engine.needsClock)
        engine.nativeTransforms = false; events = []
        engine.update(pair(), at: 4); engine.update([], at: 4.05)
        precondition(events.filter { $0 == .click }.count == 1 && !engine.needsClock)
        print("Two-finger smart zoom, right-click delay, spatial separation and cancellation checks passed")
    }
}
