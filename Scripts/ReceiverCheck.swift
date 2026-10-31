import AppKit
import ApplicationServices
import Network

/// Runs the production receiver and client with an event recorder instead of OS posting.
/// No cursor movement, window activation, clicks or scrolls are sent to the desktop.
@main struct ReceiverCheck {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "ReceiverCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func wait(_ message: String, seconds: Double = 3, until condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, message)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("Receiver check failed: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        guard AXIsProcessTrusted() else { print("Existing Accessibility authorization is required by the production pairing gate; no permission was requested."); exit(2) }
        var events: [CGEvent] = []
        let suite = "dev.phonetouchpad.receiver-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let receiver = Receiver(port: .any, advertise: false, preferences: preferences, postEvent: { events.append($0) })
        defer { receiver.stop() }
        receiver.pointerAcceleration = false; receiver.pointerSpeed = 1
        try await wait("Listener did not start") { receiver.boundPort != nil }
        let port = receiver.boundPort!
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        let client = Connection(discover: false)
        defer { client.disconnect() }
        client.connect(endpoint: endpoint, code: receiver.code)
        try await wait("Actual client and receiver did not pair") { client.connected && receiver.connected }
        try require(client.nativeGestures == NativeGestures.supported, "Capability negotiation mismatch")
        var source = GestureEngine(); source.nativeTransforms = client.nativeGestures
        var time = ProcessInfo.processInfo.systemUptime
        source.emit = { kind, x, y, fingers in client.send(kind, x: x, y: y, fingers: fingers, at: time) }
        func feed(_ points: [TouchPoint]) { time = ProcessInfo.processInfo.systemUptime; source.update(points, at: time) }
        func pair(_ length: Double = 100, y: Double = 0) -> [TouchPoint] {
            [TouchPoint(id: 1, x: -length / 2, y: y), TouchPoint(id: 2, x: length / 2, y: y)]
        }
        func native(_ type: NSEvent.EventType, _ phase: NSEvent.Phase) -> Bool {
            events.contains { guard let event = NSEvent(cgEvent: $0) else { return false }; return event.type == type && event.phase == phase }
        }
        func pause() async throws { try await Task.sleep(nanoseconds: 20_000_000) }
        feed(pair()); try await pause(); feed(pair(112.5)); try await pause(); feed([])
        try await wait("Gesture engine did not reach native zoom output") { native(.magnify, .ended) }
        let zoom = events.compactMap { NSEvent(cgEvent: $0) }.first { $0.type == .magnify && $0.phase == .changed }
        try require(abs((zoom?.magnification ?? 0) - 0.125) < 0.00001, "Pinch scale changed in transit")

        // Real source timestamps, receiver phase state and asynchronous momentum timer.
        feed(pair()); try await pause(); feed(pair(y: 12)); try await pause(); feed(pair(y: 24)); try await pause(); feed([])
        try await wait("Receiver momentum timer did not run") { events.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventMomentumPhase) == 2 } }
        client.send(.contact)
        try await wait("Contact did not stop momentum") { events.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventMomentumPhase) == 3 } }
        let stoppedCount = events.count
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(events.count == stoppedCount, "Momentum continued after contact")
        let beforeSingleSample = events.count
        client.send(.scrollBegin); client.send(.scroll, y: 4); client.send(.scrollEnd)
        try await wait("Single-sample scroll did not end") { events.dropFirst(beforeSingleSample).contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 4 } }
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(!events.dropFirst(beforeSingleSample).contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 }, "Momentum ended without ever beginning")
        client.send(.click); client.send(.click)
        try await wait("Double click count was lost") { events.contains { $0.type == .leftMouseDown && $0.getIntegerValueField(.mouseEventClickState) == 2 } }

        source.threeFingerMode = .drag
        let fingers = [TouchPoint(id: 1, x: 0, y: 0), TouchPoint(id: 2, x: 50, y: 0), TouchPoint(id: 3, x: 100, y: 0)]
        feed(fingers); try await pause(); feed(fingers.map { TouchPoint(id: $0.id, x: $0.x + 12, y: $0.y) })
        try await wait("Drag did not reach event output") { events.contains { $0.type == .leftMouseDragged } }
        let ups = events.filter { $0.type == .leftMouseUp }.count
        client.disconnect()
        try await wait("Clean TCP close did not release drag") { !receiver.connected && events.filter { $0.type == .leftMouseUp }.count > ups }
        source.cancel()
        print("Real engine/client/TLS/receiver native output, momentum, multi-click and disconnect drag release passed"); fflush(stdout)

        client.connect(endpoint: endpoint, code: receiver.code)
        try await wait("Reconnect did not pair") { client.connected && receiver.connected }
        let beforeCancel = events.count
        client.send(.scrollBegin); client.send(.scroll, y: 12)
        try await wait("Scroll did not begin") { events.dropFirst(beforeCancel).contains { $0.type == .scrollWheel } }
        receiver.disconnectDevice()
        try await wait("Session suspension did not disconnect client") { !client.connected }
        try require(receiver.boundPort == port, "Session suspension stopped discovery listener")
        try require(events.dropFirst(beforeCancel).contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 8 }, "Active scroll did not receive cancellation")

        // Keep TCP alive but send no heartbeat: exercises the production watchdog.
        let quiet = NWConnection(to: endpoint, using: SecureTransport.parameters(secret: try PairingSecret(text: receiver.code)))
        defer { quiet.cancel() }
        quiet.start(queue: .main)
        try await wait("Quiet peer TLS failed") { if case .ready = quiet.state { return true }; return false }
        func send(_ kind: InputPacket.Kind, x: Double = 0, y: Double = 0) {
            quiet.send(content: InputPacket(kind: kind, x: x, y: y, time: ProcessInfo.processInfo.systemUptime).framed(), completion: .contentProcessed { _ in })
        }
        send(.pair); try await wait("Quiet peer did not pair") { receiver.connected }
        let beforeTimeout = events.count
        send(.down); send(.zoomBegin); send(.zoom, x: 0.1); send(.scrollBegin); send(.scroll, y: 4)
        try await wait("Quiet peer input did not arrive") { events.count >= beforeTimeout + 4 }
        try await wait("Watchdog did not close silent live connection", seconds: 8) { !receiver.connected }
        let cleanup = Array(events.dropFirst(beforeTimeout))
        try require(cleanup.contains { $0.type == .leftMouseUp }, "Watchdog did not release mouse")
        try require(cleanup.contains { $0.type == .scrollWheel && $0.getIntegerValueField(.scrollWheelEventScrollPhase) == 8 }, "Watchdog did not cancel scroll")
        try require(native(.magnify, .cancelled), "Watchdog did not cancel native transform")
        try require(receiver.status.contains("连接中断"), "Watchdog status was lost")
        receiver.stop()
        try require(receiver.boundPort == nil && !receiver.connected, "Stop did not close listener")
        print("Session suspension, live-peer timeout and shutdown released all active input states")
    }
}
