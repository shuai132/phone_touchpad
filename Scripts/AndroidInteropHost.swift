import Foundation
import AppKit
import Network

@main struct AndroidInteropHost {
    @MainActor static func main() async {
        do { try await run() } catch { fputs("Android interop host failed: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        var events: [CGEvent] = []
        let suite = "dev.phonetouchpad.android-interop." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let port = CommandLine.arguments.dropFirst(2).first.flatMap(UInt16.init).flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        let receiver = Receiver(port: port, advertise: false, preferences: preferences, permissionCheck: { true }, postEvent: { events.append($0) })
        defer { receiver.stop() }
        let deadline = ProcessInfo.processInfo.systemUptime + (CommandLine.arguments.dropFirst(3).first.flatMap(Double.init) ?? 60)
        while receiver.boundPort == nil {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let ready = directory.appendingPathComponent("ready.json")
        try JSONSerialization.data(withJSONObject: ["port": Int(receiver.boundPort!.rawValue), "key": receiver.code]).write(to: ready, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ready.path)
        let done = directory.appendingPathComponent("done")
        while !FileManager.default.fileExists(atPath: done.path) || receiver.connected {
            if !events.isEmpty && !receiver.connected { try Data().write(to: directory.appendingPathComponent("idle"), options: .atomic) }
            let drop = directory.appendingPathComponent("drop")
            if FileManager.default.fileExists(atPath: drop.path) {
                receiver.disconnectDevice(); try FileManager.default.removeItem(at: drop)
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let summary = events.map { event -> [String: Double] in
            let native = NSEvent(cgEvent: event)
            return ["cgType": Double(event.type.rawValue), "type": Double(native?.type.rawValue ?? 0), "phase": event.type.rawValue == 29 ? Double(native?.phase.rawValue ?? 0) : 0]
        }
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted]).write(to: directory.appendingPathComponent("events.json"), options: .atomic)
        let types = Set(events.map(\.type))
        let native = events.compactMap { NSEvent(cgEvent: $0) }.contains { $0.type == .magnify && $0.phase == .ended }
        guard types.contains(.leftMouseDown), types.contains(.leftMouseUp), types.contains(.leftMouseDragged), types.contains(.scrollWheel), native else {
            throw NSError(domain: "AndroidInterop", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Android input did not reach the real receiver"])
        }
        print("Kotlin TLS-PSK client → Swift receiver input and native transform output passed")
    }
}
