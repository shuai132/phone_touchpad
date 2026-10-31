import AppKit
import WebKit

final class PinchWebView: WKWebView {
    var resultURL: URL!
    var phases: [UInt] = []
    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        phases.append(event.phase.rawValue)
    }
}
@main struct WebPinchTarget {
    static func main() {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 500, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Touchpad web pinch test"
        let web = PinchWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
        web.allowsMagnification = true
        web.loadHTMLString("<html><body style='font:24px sans-serif;padding:40px'>Local pinch verification<br>No remote content loaded.</body></html>", baseURL: nil)
        window.contentView = web
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in app.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(web) }
        var ready = false
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if !ready && app.isActive && window.isKeyWindow && !web.isLoading {
                ready = true
                let height = NSScreen.screens.first!.frame.height
                let metadata: [String: Any] = ["pid": getpid(), "x": window.frame.midX, "y": height - window.frame.midY]
                try? JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("ready.json"), options: .atomic)
            }
            let result: [String: Any] = ["magnification": web.magnification, "phases": web.phases]
            try? JSONSerialization.data(withJSONObject: result).write(to: directory.appendingPathComponent("result.json"), options: .atomic)
        }
        Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { _ in app.terminate(nil) }
        app.run()
    }
}
