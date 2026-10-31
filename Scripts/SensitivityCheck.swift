import AppKit
import Network

@main struct SensitivityCheck {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    @MainActor static func main() async throws {
        let full = NativeGestures.scaledMagnification(0.44, sensitivity: 0.35)
        let half = NativeGestures.scaledMagnification(0.2, sensitivity: 0.35)
        precondition(abs((1 + half) * (1 + half) - (1 + full)) < 1e-12, "Zoom depends on sample splitting")
        let reverse = NativeGestures.scaledMagnification(1 / 1.44 - 1, sensitivity: 0.35)
        precondition(abs((1 + full) * (1 + reverse) - 1) < 1e-12, "Pinch-in and pinch-out are asymmetric")
        precondition(NativeGestures.scaledMagnification(.nan, sensitivity: 0.35) == 0)
        let suite = "dev.phonetouchpad.sensitivity." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        var events: [CGEvent] = []
        let receiver = Receiver(port: .any, advertise: false, preferences: prefs, permissionCheck: { true }, postEvent: { events.append($0) })
        defer { receiver.stop() }
        precondition(receiver.scrollSensitivity == 1 && receiver.zoomSensitivity == 0.35)
        receiver.naturalScrolling = true
        try await wait { receiver.boundPort != nil }
        let client = Connection(discover: false)
        defer { client.disconnect() }
        client.connect(route: .localNetwork(host: "127.0.0.1", port: receiver.boundPort!.rawValue), code: receiver.code)
        try await wait { client.connected }
        for gain in [0.2, 1.0, 2.0] {
            events.removeAll(); receiver.scrollSensitivity = gain
            client.send(.contact); client.send(.scrollBegin); client.send(.scroll, y: 20, at: 100)
            try await wait { events.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 } }
            let event = events.first { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 }!
            precondition(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == Int64(20 * gain))
            client.send(.reset)
            try await wait { events.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 8 } }
        }
        events.removeAll(); receiver.scrollSensitivity = 1
        client.send(.scrollBegin); client.send(.scroll, y: 20, at: 200)
        client.send(.scroll, y: 20, at: 200.02); client.send(.scrollEnd, at: 200.03)
        try await wait { events.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 } }
        receiver.scrollSensitivity = 0.4
        precondition(events.last?.getIntegerValueField(.scrollWheelEventMomentumPhase) == 3, "Changing gain did not stop existing momentum")
        let stoppedCount = events.count
        try await Task.sleep(nanoseconds: 80_000_000)
        precondition(events.count == stoppedCount, "Old momentum continued after a sensitivity change")
        for gain in [0.1, 0.35, 1.0] {
            events.removeAll(); receiver.zoomSensitivity = gain
            client.send(.zoomBegin); client.send(.zoom, x: 0.2); client.send(.zoomEnd)
            try await wait { events.compactMap { NSEvent(cgEvent: $0) }.contains { $0.type == .magnify && $0.phase == .ended } }
            let value = events.compactMap { NSEvent(cgEvent: $0) }.first { $0.type == .magnify && $0.phase == .changed }!.magnification
            precondition(abs(value - (pow(1.2, gain) - 1)) < 1e-6)
        }
        receiver.scrollSensitivity = 0.4; receiver.zoomSensitivity = 0.25
        let restored = Receiver(port: .any, advertise: false, preferences: prefs, permissionCheck: { true }, postEvent: { _ in })
        precondition(restored.scrollSensitivity == 0.4 && restored.zoomSensitivity == 0.25)
        restored.stop()
        print("Scroll gain, softer default pinch, sample independence, symmetry and persistence passed through real TLS receiver")
    }
}
