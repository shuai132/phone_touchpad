import Foundation
@main struct ScrollLiftCheck {
    static func main() {
        var events: [InputPacket.Kind] = []
        var engine = GestureEngine()
        engine.emit = { kind, _, _, _ in events.append(kind) }
        let first = TouchPoint(id: 1, x: 0, y: 0), second = TouchPoint(id: 2, x: 100, y: 0)
        engine.update([first, second], at: 0)
        engine.update([TouchPoint(id: 1, x: 0, y: 15), TouchPoint(id: 2, x: 100, y: 15)], at: 0.02)
        engine.update([TouchPoint(id: 1, x: 0, y: 15)], at: 0.03)
        precondition(!events.contains(.scrollEnd) && events.filter { $0 == .contact }.count == 1)
        engine.update([], at: 0.04)
        precondition(events.filter { $0 == .scrollEnd }.count == 1)
        engine.cancel(); events = []
        engine.update([first, second], at: 1)
        engine.update([TouchPoint(id: 1, x: 0, y: 15), TouchPoint(id: 2, x: 100, y: 15)], at: 1.02)
        engine.update([TouchPoint(id: 1, x: 0, y: 15)], at: 1.03)
        engine.update([TouchPoint(id: 1, x: 0, y: 15), TouchPoint(id: 3, x: 100, y: 15)], at: 1.04)
        precondition(events.filter { $0 == .scrollEnd }.count == 1 && events.filter { $0 == .contact }.count == 2)
        events = []; engine.cancel()
        precondition(events == [.reset])
        print("Staggered finger lift, replacement contact and cancelled scroll phase checks passed")
    }
}
