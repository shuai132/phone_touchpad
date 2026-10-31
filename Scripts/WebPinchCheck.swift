import AppKit
import ApplicationServices
import Network

@main struct WebPinchCheck {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    @MainActor static func main() async throws {
        guard AXIsProcessTrusted() else { print("Existing Accessibility permission required; none requested."); exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let launch = Process(); launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = ["-n", directory.appendingPathComponent("WebPinchTarget.app").path, "--args", directory.path]
        try launch.run(); launch.waitUntilExit()
        try await wait { FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready.json").path) }
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("ready.json"))) as! [String: Any]
        let pid = (metadata["pid"] as! NSNumber).int32Value
        defer { if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "dev.phonetouchpad.webpinchtarget" { kill(pid, SIGTERM) } }
        let old = CGEvent(source: nil)!.location
        CGWarpMouseCursorPosition(CGPoint(x: (metadata["x"] as! NSNumber).doubleValue, y: (metadata["y"] as! NSNumber).doubleValue))
        defer { CGWarpMouseCursorPosition(old) }
        let suite = "dev.phonetouchpad.webpinch." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let receiver = Receiver(port: .any, advertise: false, preferences: preferences)
        defer { receiver.stop() }
        try await wait { receiver.boundPort != nil }
        let client = Connection(discover: false)
        defer { client.disconnect() }
        client.connect(route: .localNetwork(host: "127.0.0.1", port: receiver.boundPort!.rawValue), code: receiver.code)
        try await wait { client.connected }
        var engine = GestureEngine(); engine.nativeTransforms = client.nativeGestures
        var time = ProcessInfo.processInfo.systemUptime
        engine.emit = { kind, x, y, fingers in client.send(kind, x: x, y: y, fingers: fingers, at: time) }
        for separation in [100.0, 110, 120, 130, 140, 150] {
            precondition(NSRunningApplication(processIdentifier: pid)?.isActive == true, "Web test target lost focus")
            time = ProcessInfo.processInfo.systemUptime
            engine.update([TouchPoint(id: 1, x: -separation / 2, y: 0), TouchPoint(id: 2, x: separation / 2, y: 0)], at: time)
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        time = ProcessInfo.processInfo.systemUptime; engine.update([], at: time)
        var result: [String: Any] = [:]
        try await wait {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("result.json")), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { result = value }
            return (result["phases"] as? [UInt])?.contains(NSEvent.Phase.ended.rawValue) == true
        }
        print("Web view result:", result)
        precondition((result["magnification"] as? Double ?? 1) > 1.1, "Native pinch phases arrived but actual web magnification did not change")
        print("Real gesture engine/client/TLS/receiver pinch magnified a WKWebView")
    }
}
