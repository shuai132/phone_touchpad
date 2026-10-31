import Foundation

@main struct TapDragCheck {
    static func main() {
        var events: [(InputPacket.Kind, Double)] = []
        var pad = GestureEngine()
        pad.tapToDrag = true
        pad.emit = { kind, x, _, _ in events.append((kind, x)) }
        func p(_ x: Double, id: Int = 1) -> TouchPoint { TouchPoint(id: id, x: x, y: 0) }
        // The second contact holds cursor motion until it either becomes a tap or starts dragging.
        pad.update([p(0)], at: 0); pad.update([], at: 0.05)
        pad.update([p(0)], at: 0.15)
        pad.update([p(2)], at: 0.17)
        precondition(!events.contains { $0.0 == .down || $0.0 == .move })
        pad.update([p(7)], at: 0.18); pad.update([p(15)], at: 0.23)
        pad.update([], at: 0.25)
        precondition(events.filter { $0.0 == .click }.count == 1)
        precondition(events.filter { $0.0 == .down }.count == 1 && events.filter { $0.0 == .up }.count == 1)
        precondition(events.filter { $0.0 == .move }.reduce(0) { $0 + $1.1 } == 15)
        pad.cancel(); events = []
        // A quick second tap remains a double click, not a mouse-down held across taps.
        pad.update([p(0)], at: 1); pad.update([], at: 1.05)
        pad.update([p(0)], at: 1.15); pad.update([], at: 1.2)
        precondition(events.filter { $0.0 == .click }.count == 2 && !events.contains { $0.0 == .down })
        pad.cancel(); events = []
        // A stationary second hold starts dragging using the clock, without requiring a move event.
        pad.update([p(0)], at: 2); pad.update([], at: 2.05)
        pad.update([p(0)], at: 2.15); pad.advance(at: 2.36)
        pad.advance(at: 2.5)
        precondition(events.filter { $0.0 == .down }.count == 1)
        pad.update([p(0), p(20, id: 2)], at: 2.55)
        pad.update([], at: 2.6)
        precondition(events.filter { $0.0 == .up }.count == 1 && events.filter { $0.0 == .click }.count == 1)
        pad.cancel(); events = []
        // A far-away second touch is a new pointer gesture, as is an expired second touch.
        pad.update([p(0)], at: 3); pad.update([], at: 3.05)
        pad.update([p(80)], at: 3.15); pad.update([p(100)], at: 3.2); pad.update([], at: 3.3)
        precondition(!events.contains { $0.0 == .down })
        pad.cancel(); events = []
        pad.update([p(0)], at: 4); pad.update([], at: 4.05)
        pad.update([p(0)], at: 4.5); pad.update([p(20)], at: 4.6); pad.update([], at: 4.7)
        precondition(!events.contains { $0.0 == .down })
        pad.cancel(); events = []
        pad.tapToClick = false
        pad.update([p(0)], at: 5); pad.update([], at: 5.05)
        pad.update([p(0)], at: 5.1); pad.advance(at: 5.4); pad.update([], at: 5.5)
        precondition(!events.contains { $0.0 == .click || $0.0 == .down })
        pad.cancel(); events = []
        // Individual finger motion must not be mistaken for a coherent multi-finger swipe.
        pad.update([p(0), p(20, id: 2), p(40, id: 3)], at: 6)
        pad.update([p(100), p(20, id: 2), p(40, id: 3)], at: 6.1)
        precondition(!events.contains { $0.0 == .swipe })
        pad.cancel(); events = []
        // Cancellation forgets pending tap-drag eligibility.
        pad.tapToClick = true
        pad.update([p(0)], at: 7); pad.update([], at: 7.05); pad.cancel()
        pad.update([p(0)], at: 7.1); pad.advance(at: 7.4)
        precondition(!events.contains { $0.0 == .down })
        pad.cancel(); events = []
        pad.update([p(0)], at: 8); pad.update([], at: 8.05)
        pad.update([p(0)], at: 8.1); pad.advance(at: 8.4)
        precondition(events.filter { $0.0 == .down }.count == 1)
        pad.cancel()
        precondition(events.last?.0 == .reset)
        events = []
        pad.update([p(0)], at: 8.5); pad.advance(at: 8.8)
        precondition(!events.contains { $0.0 == .down })
        print("Tap-drag, double-tap and multi-finger coherence checks passed")
    }
}
