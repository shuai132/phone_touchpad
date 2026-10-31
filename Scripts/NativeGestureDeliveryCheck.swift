import AppKit
import ApplicationServices

@main struct NativeGestureDeliveryCheck {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "NativeGestureDelivery", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func main() throws {
        guard AXIsProcessTrusted() else { print("Delivery test requires existing Accessibility authorization; no permission was requested."); exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let launch = Process(); launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launch.arguments = ["-n", directory.appendingPathComponent("GestureTarget.app").path, "--args", directory.path]
        try launch.run(); launch.waitUntilExit()
        let ready = directory.appendingPathComponent("ready.json")
        let deadline = Date().addingTimeInterval(35)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: ready)) as! [String: Any]
        guard metadata["active"] as? Bool == true else { print("Test target did not activate"); exit(3) }
        let pid = (metadata["pid"] as! NSNumber).int32Value
        defer {
            if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "dev.phonetouchpad.gesturetarget" { kill(pid, SIGTERM) }
        }
        let location = CGPoint(x: (metadata["x"] as! NSNumber).doubleValue, y: (metadata["y"] as! NSNumber).doubleValue)
        let oldLocation = CGEvent(source: nil)!.location
        CGWarpMouseCursorPosition(location)
        defer { CGWarpMouseCursorPosition(oldLocation) }
        for kind in NativeGestures.Kind.allCases {
            for phase in (kind == .smartZoom ? [NativeGestures.Phase.none] : [.began, .changed, .ended]) {
                try require(NSRunningApplication(processIdentifier: pid)?.isActive == true, "Test target lost focus")
                let event = NativeGestures.event(kind: kind, value: phase == .changed ? 0.125 : 0, phase: phase, location: location)!
                event.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("result.json"))) as! [[String: Double]]
        let types = result.compactMap { $0["type"] }
        try require(types == [30, 30, 30, 18, 18, 18, 32], "Event type order mismatch")
        try require(result[1]["value"] == 0.125 && result[4]["value"] == 0.125, "Gesture values changed")
        let expectedPhases: [NSEvent.Phase] = [.began, .changed, .ended, .began, .changed, .ended, []]
        try require(result.compactMap { $0["phase"] } == expectedPhases.map { Double($0.rawValue) }, "Gesture phase mismatch")
        try require((result[2]["magnification"] ?? 0) > 1, "AppKit scroll view did not magnify")
        print("Cross-process native gesture delivery and built-in NSScrollView magnification passed")
    }
}
