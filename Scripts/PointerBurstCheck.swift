import AppKit
import Network

/// The recorder deliberately leaves the OS cursor stationary, reproducing queued posting.
@main struct PointerBurstCheck {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    @MainActor static func main() async throws {
        var events: [CGEvent] = []
        let suite = "dev.phonetouchpad.pointer." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let receiver = Receiver(port: .any, advertise: false, preferences: preferences, permissionCheck: { true }, postEvent: { events.append($0) })
        defer { receiver.stop() }
        receiver.pointerAcceleration = false; receiver.pointerSpeed = 1
        try await wait { receiver.boundPort != nil }
        let client = Connection(discover: false)
        defer { client.disconnect() }
        client.connect(route: .localNetwork(host: "127.0.0.1", port: receiver.boundPort!.rawValue), code: receiver.code)
        try await wait { client.connected }
        let actual = CGEvent(source: nil)!.location
        let screen = NSScreen.screens.first!.frame
        let step = actual.x < screen.midX ? 2.0 : -2.0
        client.send(.contact)
        for i in 0..<3 { client.send(.move, x: step, at: 100 + Double(i) / 120) }
        client.send(.click)
        try await wait { events.contains { $0.type == .leftMouseUp } }
        let moves = events.filter { $0.type == .mouseMoved }
        precondition(moves.count == 3)
        for i in 0..<3 {
            precondition(abs(moves[i].location.x - (actual.x + Double(i + 1) * step * 1.5)) < 0.001, "Queued movement lost accumulated displacement")
        }
        precondition(events.filter { $0.type == .leftMouseDown || $0.type == .leftMouseUp }.allSatisfy { $0.location == moves.last!.location }, "Click did not use latest queued cursor position")
        // A fresh touch reacquires the real pointer; stale virtual coordinates must not persist.
        events.removeAll(); client.send(.reset); client.send(.contact); client.send(.move, x: step, at: 200)
        try await wait { events.contains { $0.type == .mouseMoved } }
        precondition(abs(events.last!.location.x - (actual.x + step * 1.5)) < 0.001)
        events.removeAll()
        var engine = GestureEngine()
        var time = 300.0
        engine.emit = { kind, x, y, fingers in client.send(kind, x: x, y: y, fingers: fingers, at: time) }
        for index in 0..<2 {
            time = 300 + Double(index) * 0.1
            engine.update([TouchPoint(id: 1, x: 0, y: 0, pressure: 0.1)], at: time)
            time += 0.01; engine.update([TouchPoint(id: 1, x: 0, y: 0, pressure: 0.7)], at: time)
            time += 0.01; engine.update([], at: time)
        }
        try await wait { events.filter { $0.type == .leftMouseUp }.count == 2 }
        let downs = events.filter { $0.type == .leftMouseDown }.map { $0.getIntegerValueField(.mouseEventClickState) }
        let ups = events.filter { $0.type == .leftMouseUp }.map { $0.getIntegerValueField(.mouseEventClickState) }
        precondition(downs == [1, 2] && ups == downs, "Physical press double-click counts differ between down and up")
        events.removeAll(); engine.cancel()
        for (offset, pressure) in [(0.0, 0.7), (step, 0.7), (step, 0.2), (2 * step, 0.2)] {
            time += 0.01
            engine.update([TouchPoint(id: 1, x: offset, y: 0, pressure: pressure)], at: time)
        }
        time += 0.01; engine.update([], at: time)
        try await wait { events.filter { $0.type == .mouseMoved || $0.type == .leftMouseDragged }.count == 2 }
        let continued = events.filter { $0.type == .mouseMoved || $0.type == .leftMouseDragged }
        precondition(continued[0].type == .leftMouseDragged && continued[1].type == .mouseMoved)
        precondition(abs(continued[1].location.x - (actual.x + 2 * step * 1.5)) < 0.001, "Pressure release lost continued contact displacement")
        print("Queued pointer displacement, click alignment and fresh-contact anchoring passed")
        print("Pressure engine through actual client/TLS/receiver preserved physical double-click counts")
        print("Pressure release kept continuous pointer coordinates without ending the touch")
    }
}
