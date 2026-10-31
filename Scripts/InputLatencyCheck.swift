import Foundation
import AppKit
import Network

/// Measures a local production path with an event recorder; never posts to the desktop.
@main struct InputLatencyCheck {
    static func report(_ name: String, _ samples: [Double]) {
        let values = samples.sorted()
        func percentile(_ p: Double) -> Double { values[min(Int(Double(values.count - 1) * p), values.count - 1)] }
        print(String(format: "%@: n=%d p50=%.4f ms p95=%.4f ms p99=%.4f ms", name, values.count, percentile(0.5), percentile(0.95), percentile(0.99)))
    }
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    @MainActor static func main() async throws {
        var encoding: [Double] = [], decoding: [Double] = []
        let packet = InputPacket(kind: .move, x: 2.5, y: -1.75, time: 1234.5)
        for index in 0..<5500 {
            let start = ProcessInfo.processInfo.systemUptime
            let bytes = packet.framed()
            let encoded = ProcessInfo.processInfo.systemUptime
            var buffer = PacketBuffer()
            let decoded = try buffer.append(bytes)
            let end = ProcessInfo.processInfo.systemUptime
            precondition(decoded.count == 1 && decoded[0].x == packet.x)
            if index >= 500 { encoding.append((encoded - start) * 1000); decoding.append((end - encoded) * 1000) }
        }
        report("JSON encode + newline", encoding); report("JSON frame + decode", decoding)

        let suite = "dev.phonetouchpad.latency." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var sent: [Double] = [], delivered: [Double] = []
        let receiver = Receiver(port: .any, advertise: false, preferences: preferences, permissionCheck: { true }) { event in
            guard event.type == .mouseMoved, delivered.count < sent.count else { return }
            delivered.append((ProcessInfo.processInfo.systemUptime - sent[delivered.count]) * 1000)
        }
        defer { receiver.stop() }
        try await wait { receiver.boundPort != nil }
        let client = Connection(discover: false)
        defer { client.disconnect() }
        client.connect(route: .forwardedTCP(host: "127.0.0.1", port: receiver.boundPort!.rawValue), code: receiver.code)
        try await wait { client.connected }
        // Pace at a representative input rate; include encode, scheduling, TLS,
        // receiver parsing and CGEvent construction, but no actual event delivery.
        for index in 0..<360 {
            sent.append(ProcessInfo.processInfo.systemUptime)
            client.send(.move, x: index.isMultiple(of: 2) ? 1 : -1, at: sent.last!)
            try await Task.sleep(nanoseconds: 8_333_333)
        }
        try await wait { delivered.count == sent.count }
        report("Local TLS client to recorded CGEvent (120 Hz requested; excludes display)", Array(delivered.dropFirst(60)))
        print("Not a Wi-Fi, USB, iPhone touch-to-display, or hardware latency measurement.")
    }
}
