import AppKit
import ApplicationServices
import Network

@main struct InputChainCheck {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "InputChainCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func wait(_ message: String, seconds: Double = 3, until condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, message)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("Input-chain check failed: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        guard AXIsProcessTrusted() else { print("Input-chain test requires existing Accessibility authorization; none was requested."); exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let resultURL = directory.appendingPathComponent("result.json")
        var completed = false
        func records() -> [[String: Double]] {
            guard let data = try? Data(contentsOf: resultURL) else { return [] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Double]] ?? []
        }
        defer { if !completed { print("Observed target records:", records()); fflush(stdout) } }
        let launch = Process(); launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = ["-n", directory.appendingPathComponent("GestureTarget.app").path, "--args", directory.path]
        try launch.run(); launch.waitUntilExit()
        let ready = directory.appendingPathComponent("ready.json")
        try await wait("Test target did not activate", seconds: 50) { FileManager.default.fileExists(atPath: ready.path) }
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: ready)) as! [String: Any]
        let pid = (metadata["pid"] as! NSNumber).int32Value
        defer {
            if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "dev.phonetouchpad.gesturetarget" { kill(pid, SIGTERM) }
        }
        let location = CGPoint(x: (metadata["x"] as! NSNumber).doubleValue, y: (metadata["y"] as! NSNumber).doubleValue)
        let oldLocation = CGEvent(source: nil)!.location
        CGWarpMouseCursorPosition(location)
        defer { CGWarpMouseCursorPosition(oldLocation) }

        let suite = "dev.phonetouchpad.test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let receiver = Receiver(port: .any, advertise: false, preferences: preferences)
        defer { receiver.stop() }
        receiver.pointerAcceleration = false; receiver.pointerSpeed = 1
        try await wait("Receiver did not start") { receiver.boundPort != nil }
        let client = Connection(discover: false)
        defer { client.disconnect() }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: receiver.boundPort!)
        client.connect(endpoint: endpoint, code: receiver.code)
        try await wait("Real client and receiver did not pair") { client.connected && receiver.connected }
        try require(client.nativeGestures, "Native gesture capability was not negotiated")


        var engine = GestureEngine(); engine.nativeTransforms = client.nativeGestures
        var time = ProcessInfo.processInfo.systemUptime
        engine.emit = { kind, x, y, fingers in client.send(kind, x: x, y: y, fingers: fingers, at: time) }
        func feed(_ points: [TouchPoint]) throws {
            try require(NSRunningApplication(processIdentifier: pid)?.isActive == true, "Test target lost focus")
            time = ProcessInfo.processInfo.systemUptime; engine.update(points, at: time)
        }
        func pair(length: Double = 100, angle: Double = 0, y: Double = 0) -> [TouchPoint] {
            let dx = cos(angle) * length / 2, dy = sin(angle) * length / 2
            return [TouchPoint(id: 1, x: -dx, y: y - dy), TouchPoint(id: 2, x: dx, y: y + dy)]
        }
        func pause(_ milliseconds: UInt64 = 40) async throws { try await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
        try feed(pair()); try await pause(); try feed(pair(length: 112.5)); try await pause(); try feed([])
        try await wait("Pinch did not magnify the target") { records().contains { $0["type"] == 30 && ($0["magnification"] ?? 0) > 1 } }
        try feed(pair()); try await pause(); try feed(pair(angle: 0.2)); try await pause(); try feed([])
        try await wait("Rotation did not reach target") { records().contains { $0["type"] == 18 && abs(($0["value"] ?? 0) + 0.2 * 180 / .pi) < 0.001 } }
        try feed(pair()); try await pause(); try feed([]); try await pause(); try feed(pair()); try await pause(); try feed([])
        try await wait("Smart zoom did not reach target") { records().contains { $0["type"] == 32 } }
        print("Gesture engine → real client → TLS → real receiver → AppKit transforms passed"); fflush(stdout)

        // Exercise the production scroll phase and momentum timer, not a model of it.
        try feed(pair()); try await pause(); try feed(pair(y: 15)); try await pause(); try feed(pair(y: 30)); try await pause(); try feed([])
        try await wait("Scroll momentum did not reach target") { records().contains { $0["type"] == 22 && ($0["momentum"] ?? 0) != 0 } }
        client.send(.contact)
        try await wait("New contact did not stop momentum") { records().contains { $0["type"] == 22 && $0["momentum"] == Double(NSEvent.Phase.ended.rawValue) } }
        let momentumCount = records().count
        try await pause(150)
        try require(records().count == momentumCount, "Momentum continued after contact")

        // Taps pass through the same engine used by the UIView adapter.
        try feed([TouchPoint(id: 1, x: 0, y: 0)]); try await pause(); try feed([])
        try await pause()
        try feed([TouchPoint(id: 1, x: 0, y: 0)]); try await pause(); try feed([])
        try await wait("Double-click count did not reach target") { records().contains { $0["type"] == 1 && $0["clicks"] == 2 } }
        try feed(pair()); try await pause(); try feed([]); try await pause(300)
        time = ProcessInfo.processInfo.systemUptime; engine.advance(at: time)
        try await wait("Right click did not reach target") { records().contains { $0["type"] == 3 } }

        engine.threeFingerMode = .drag
        let three = [TouchPoint(id: 1, x: 0, y: 0), TouchPoint(id: 2, x: 50, y: 0), TouchPoint(id: 3, x: 100, y: 0)]
        try feed(three); try await pause(); try feed(three.map { TouchPoint(id: $0.id, x: $0.x + 12, y: $0.y) })
        try await wait("Three-finger drag did not reach target") { records().contains { $0["type"] == 6 } }
        let upBefore = records().filter { $0["type"] == 2 }.count
        client.disconnect()
        try await wait("TCP close did not release mouse") { !receiver.connected && records().filter { $0["type"] == 2 }.count > upBefore }
        engine.cancel()
        print("Actual scroll/momentum, click counts, right click and disconnect drag release passed"); fflush(stdout)

        // A live TLS peer that stops sending is different from a clean TCP close.
        let quiet = NWConnection(to: endpoint, using: SecureTransport.parameters(secret: try PairingSecret(text: receiver.code)))
        defer { quiet.cancel() }
        quiet.start(queue: .main)
        try await wait("Silent peer TLS handshake failed") { if case .ready = quiet.state { return true }; return false }
        func raw(_ kind: InputPacket.Kind, x: Double = 0) throws {
            try require(NSRunningApplication(processIdentifier: pid)?.isActive == true, "Test target lost focus")
            quiet.send(content: InputPacket(kind: kind, x: x, time: ProcessInfo.processInfo.systemUptime).framed(), completion: .contentProcessed { _ in })
        }
        try raw(.pair)
        try await wait("Silent peer did not pair") { receiver.connected }
        let before = records().count
        try raw(.down); try raw(.scrollBegin); try raw(.scroll, x: 12)
        try await wait("Silent peer input did not reach target") { records().dropFirst(before).contains { $0["type"] == 1 } }
        try await wait("Watchdog did not close live unresponsive peer", seconds: 8) { !receiver.connected }
        try await wait("Watchdog did not release active scroll and mouse") {
            let tail = records().dropFirst(before)
            return tail.contains { $0["type"] == 2 } && tail.contains { $0["type"] == 22 && $0["phase"] == Double(NSEvent.Phase.cancelled.rawValue) }
        }
        try require(receiver.status.contains("连接中断"), "Unexpected watchdog status")
        completed = true
        print("Live unresponsive TLS peer watchdog released mouse and cancelled scroll")
    }
}
