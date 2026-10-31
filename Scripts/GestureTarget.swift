import AppKit

final class GestureTargetView: NSScrollView {
    var received: [[String: Double]] = []
    var resultURL: URL!
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ rect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); rect.fill()
        ("Touchpad native gesture test" as NSString).draw(at: NSPoint(x: 24, y: 90), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
    }
    fileprivate func record(_ event: NSEvent, value: Double) {
        let mouse: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp]
        received.append(["type": Double(event.type.rawValue), "phase": mouse.contains(event.type) ? 0 : Double(event.phase.rawValue), "value": value, "magnification": magnification, "clicks": mouse.contains(event.type) ? Double(event.clickCount) : 0, "momentum": event.type == .scrollWheel ? Double(event.momentumPhase.rawValue) : 0])
        try? JSONSerialization.data(withJSONObject: received).write(to: resultURL, options: .atomic)
    }
    override func magnify(with event: NSEvent) { super.magnify(with: event); record(event, value: event.magnification) }
    override func scrollWheel(with event: NSEvent) { super.scrollWheel(with: event); record(event, value: event.scrollingDeltaY) }
    override func rotate(with event: NSEvent) { record(event, value: Double(event.rotation)) }
    override func smartMagnify(with event: NSEvent) { record(event, value: 0) }
}
final class GestureTargetDocument: NSView {
    weak var owner: GestureTargetView?
    override func mouseDown(with event: NSEvent) { owner?.record(event, value: 0) }
    override func mouseUp(with event: NSEvent) { owner?.record(event, value: 0) }
    override func mouseDragged(with event: NSEvent) { owner?.record(event, value: 0) }
    override func rightMouseDown(with event: NSEvent) { owner?.record(event, value: 0) }
    override func rightMouseUp(with event: NSEvent) { owner?.record(event, value: 0) }
}
@main struct GestureTarget {
    static func main() {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 340, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Touchpad gesture test"
        let view = GestureTargetView(frame: NSRect(x: 0, y: 0, width: 340, height: 200))
        view.allowsMagnification = true
        view.minMagnification = 0.25; view.maxMagnification = 4
        let document = GestureTargetDocument(frame: NSRect(x: 0, y: 0, width: 680, height: 400))
        document.owner = view; view.documentView = document
        view.resultURL = directory.appendingPathComponent("result.json")
        view.allowedTouchTypes = [.direct, .indirect]
        window.contentView = view
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
            app.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            guard app.isActive && window.isKeyWindow else { return }
            timer.invalidate()
            let height = NSScreen.screens.first!.frame.height
            let metadata: [String: Any] = ["pid": getpid(), "window": window.windowNumber, "x": window.frame.midX, "y": height - window.frame.midY, "active": app.isActive]
            try? JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("ready.json"), options: .atomic)
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in app.terminate(nil) }
        app.run()
    }
}
