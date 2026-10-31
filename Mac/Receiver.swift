import Foundation
import AppKit
import Combine
import Network
import ApplicationServices

// Network callbacks and timers execute on the main queue.
final class Receiver: ObservableObject {
    @Published private(set) var code = PairingSecret.generate().text
    @Published var status = "等待手机连接"
    @Published private(set) var boundPort: NWEndpoint.Port?
    @Published private(set) var connected = false
    private let listenPort: NWEndpoint.Port
    private let advertise: Bool
    private let preferences: UserDefaults
    private let postEvent: (CGEvent) -> Void
    private let permissionCheck: () -> Bool
    private func emit(_ event: CGEvent?) { if let event { postEvent(event) } }
    private let serviceName = (Host.current().localizedName ?? "Mac") + "-" + UUID().uuidString.prefix(6)
    var invitation: String {
        guard let secret = try? PairingSecret(text: code) else { return "" }
        return PairingInvitation(name: serviceName, secret: secret).url.absoluteString
    }
    @Published var pointerSpeed: Double {
        didSet { preferences.set(pointerSpeed, forKey: "pointerSpeed") }
    }
    @Published var pointerAcceleration: Bool {
        didSet { preferences.set(pointerAcceleration, forKey: "pointerAcceleration") }
    }
    @Published var naturalScrolling: Bool {
        didSet { preferences.set(naturalScrolling, forKey: "naturalScrolling") }
    }
    private var pointer = PointerMotion()
    // Posted events can still be queued when the next touch sample arrives.
    // Accumulate their destination instead of rereading a lagging OS position.
    private var cursorPosition: CGPoint?
    private var native = NativeGestures()
    private var watchdog: DispatchSourceTimer?
    private var lastReceived = 0.0
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var authenticated: UUID?
    private var dragging = false
    private var lastClickTime = 0.0
    private var lastClickPosition = CGPoint.zero
    private var lastClickButton: CGMouseButton = .left
    private var clickCount: Int64 = 0
    private var momentum = ScrollMomentum()
    private var momentumTimer: DispatchSourceTimer?
    private var momentumStarted = false
    private var scrollRemainder = (x: 0.0, y: 0.0)
    private var lastTick = 0.0
    private var firstScroll = false
    private var scrolling = false
    private func cancelScroll() {
        if scrolling { scroll(x: 0, y: 0, phase: 8); scrolling = false }
    }
    private func stopMomentum() {
        if momentumStarted { scroll(x: 0, y: 0, momentumPhase: 3) }
        momentumStarted = false
        momentumTimer?.cancel(); momentumTimer = nil; momentum.reset()
        scrollRemainder = (0, 0)
    }
    private func scroll(x: Double, y: Double, phase: Int64 = 0, momentumPhase: Int64 = 0) {
        scrollRemainder.x += x; scrollRemainder.y += y
        let ix = Int32(scrollRemainder.x.rounded()), iy = Int32(scrollRemainder.y.rounded())
        scrollRemainder.x -= Double(ix); scrollRemainder.y -= Double(iy)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: iy, wheel2: ix, wheel3: 0)
        event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        emit(event)
    }
    private func startMomentum(at time: Double) {
        momentum.end(at: time)
        lastTick = ProcessInfo.processInfo.systemUptime
        var first = true
        momentumTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0 / 120, repeating: 1.0 / 120)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = now - self.lastTick; self.lastTick = now
            guard let (x, y) = self.momentum.step(seconds: dt) else { self.stopMomentum(); return }
            self.scroll(x: x, y: y, momentumPhase: first ? 1 : 2); first = false; self.momentumStarted = true
        }
        momentumTimer = timer; timer.resume()
    }
    init(port: NWEndpoint.Port = 49271, advertise: Bool = true, preferences: UserDefaults = .standard, permissionCheck: @escaping () -> Bool = AXIsProcessTrusted, postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.permissionCheck = permissionCheck
        self.postEvent = postEvent; native = NativeGestures(postEvent: postEvent)
        self.listenPort = port; self.advertise = advertise; self.preferences = preferences
        pointerSpeed = preferences.object(forKey: "pointerSpeed") as? Double ?? 1
        pointerAcceleration = preferences.object(forKey: "pointerAcceleration") as? Bool ?? true
        naturalScrolling = preferences.object(forKey: "naturalScrolling") as? Bool ?? true
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, let id = self.authenticated, let c = self.clients[id] else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastReceived > 5 {
                self.close(c, id: id); self.status = "连接中断，已释放输入"
            }
        }
        watchdog = timer; timer.resume()
        startListener()
    }
    deinit {
        watchdog?.cancel(); release(); listener?.cancel()
        for connection in clients.values { connection.cancel() }
    }
    func stop() {
        watchdog?.cancel(); watchdog = nil
        closeConnections(); status = "已停止接收"
    }
    func disconnectDevice() {
        for connection in clients.values { connection.cancel() }
        clients.removeAll(); authenticated = nil; connected = false; release()
        status = "等待手机连接"
    }
    private func closeConnections() {
        disconnectDevice()
        listener?.cancel(); listener = nil; boundPort = nil
    }
    private func startListener() {
        do {
            let server = try NWListener(using: SecureTransport.parameters(secret: PairingSecret(text: code)), on: listenPort)
            listener = server
            if advertise { server.service = NWListener.Service(name: serviceName, type: "_phonetouchpad._tcp") }
            server.newConnectionHandler = { [weak self, weak server] connection in
                guard let self, let server, self.listener === server else { connection.cancel(); return }
                self.accept(connection)
            }
            server.stateUpdateHandler = { [weak self, weak server] state in
                guard let self, let server, self.listener === server else { return }
                switch state {
                case .ready: self.boundPort = server.port
                case .failed(let error): self.status = "监听失败：\(error.localizedDescription)"
                default: break
                }
            }
            server.start(queue: .main)
        } catch { status = error.localizedDescription }
    }
    func authorize() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func rotateCode() {
        closeConnections()
        code = PairingSecret.generate().text; status = "等待手机连接"; startListener()
    }
    private func accept(_ c: NWConnection) {
        guard clients.count < 4 else { c.cancel(); return }
        let id = UUID(); clients[id] = c
        c.start(queue: .main)
        receive(c, id: id, buffer: PacketBuffer())
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak c] in
            guard let self, self.authenticated != id else { return }
            if let c { self.close(c, id: id) }
        }
    }
    private func close(_ c: NWConnection, id: UUID) {
        c.cancel(); clients.removeValue(forKey: id)
        if authenticated == id { authenticated = nil; connected = false; release(); status = "手机已断开" }
    }
    private func reject(_ connection: NWConnection, id: UUID, reason: PairingRejection) {
        if authenticated == id { authenticated = nil; connected = false; release() }
        if authenticated == nil { status = reason.message }
        let reply = InputPacket(kind: .rejected, rejection: reason)
        connection.send(content: reply.framed(), completion: .contentProcessed { [weak self, weak connection] _ in
            guard let self, let connection else { return }
            self.close(connection, id: id)
        })
    }
    private func receive(_ c: NWConnection, id: UUID, buffer: PacketBuffer) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            guard let self, self.clients[id] === c else { return }
            var buffer = buffer
            do {
                if let data {
                    guard SecureTransport.isAuthenticatedPSK(c) else { self.close(c, id: id); return }
                    for packet in try buffer.append(data) {
                        guard packet.version == InputPacket.currentVersion else { self.reject(c, id: id, reason: .incompatibleVersion); return }
                        if packet.kind == .pair {
                            guard self.authenticated == nil || self.authenticated == id else { self.reject(c, id: id, reason: .receiverBusy); return }
                            guard self.permissionCheck() else { self.reject(c, id: id, reason: .accessibilityRequired); return }
                            self.authenticated = id; self.connected = true; self.lastReceived = ProcessInfo.processInfo.systemUptime; self.status = "手机已连接"
                            var reply = packet; reply.nativeGestures = NativeGestures.supported
                            c.send(content: reply.framed(), completion: .contentProcessed { _ in })
                        } else if self.authenticated == id {
                            self.lastReceived = ProcessInfo.processInfo.systemUptime
                            if packet.kind == .ping {
                                var reply = packet; reply.kind = .pong
                                c.send(content: reply.framed(), completion: .contentProcessed { _ in })
                            } else { self.apply(packet) }
                        } else { self.reject(c, id: id, reason: .pairingRequired); return }
                    }
                }
                if done || error != nil { self.close(c, id: id) }
                else { self.receive(c, id: id, buffer: buffer) }
            } catch { self.close(c, id: id) }
        }
    }
    private func mouse(_ type: CGEventType, button: CGMouseButton = .left, count: Int64 = 1) {
        guard let position = cursorPosition ?? CGEvent(source: nil)?.location else { return }
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: count)
        emit(event)
    }
    private func release() { native.cancel(); cancelScroll(); pointer.reset(); stopMomentum(); if dragging { mouse(.leftMouseUp); dragging = false }; cursorPosition = nil }
    private func key(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = flags; emit(e)
        }
    }
    private func apply(_ p: InputPacket) {
        guard p.x.isFinite, p.y.isFinite, abs(p.x) < 10000, abs(p.y) < 10000 else { return }
        switch p.kind {
        case .contact: cancelScroll(); stopMomentum(); pointer.reset(); cursorPosition = CGEvent(source: nil)?.location
        case .move:
            guard var point = cursorPosition ?? CGEvent(source: nil)?.location else { return }
            pointer.sensitivity = pointerSpeed; pointer.acceleration = pointerAcceleration
            let (dx, dy) = pointer.translate(x: p.x, y: p.y, at: p.time ?? ProcessInfo.processInfo.systemUptime)
            point.x += dx; point.y += dy
            let bounds = NSScreen.screens.map { $0.frame }.reduce(CGRect.null) { $0.union($1) }
            point.x = min(max(point.x, bounds.minX), bounds.maxX - 1)
            // Quartz and AppKit have different Y origins; the main screen anchors conversion.
            let height = NSScreen.screens.first?.frame.height ?? bounds.height
            point.y = min(max(point.y, height - bounds.maxY), height - bounds.minY - 1)
            cursorPosition = point
            emit(CGEvent(mouseEventSource: nil, mouseType: dragging ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
        case .click:
            let right = p.fingers == 2
            let now = ProcessInfo.processInfo.systemUptime
            let position = cursorPosition ?? CGEvent(source: nil)?.location ?? .zero
            let button: CGMouseButton = right ? .right : .left
            if now - lastClickTime <= NSEvent.doubleClickInterval && button == lastClickButton && hypot(position.x - lastClickPosition.x, position.y - lastClickPosition.y) < 4 {
                clickCount += 1
            } else { clickCount = 1 }
            lastClickTime = now; lastClickPosition = position; lastClickButton = button
            mouse(right ? .rightMouseDown : .leftMouseDown, button: button, count: clickCount)
            mouse(right ? .rightMouseUp : .leftMouseUp, button: button, count: clickCount)
        case .down: dragging = true; mouse(.leftMouseDown)
        case .up, .reset: release()
        case .scrollBegin:
            cancelScroll(); stopMomentum(); firstScroll = true; scrolling = true
        case .scroll:
            guard scrolling else { return }
            let direction = naturalScrolling ? 1.0 : -1.0
            momentum.sample(x: p.x * direction, y: p.y * direction, at: p.time ?? ProcessInfo.processInfo.systemUptime)
            scroll(x: p.x * direction, y: p.y * direction, phase: firstScroll ? 1 : 2); firstScroll = false
        case .scrollEnd:
            guard scrolling else { return }
            scroll(x: 0, y: 0, phase: 4); scrolling = false; startMomentum(at: p.time ?? ProcessInfo.processInfo.systemUptime)
        case .smartZoom: stopMomentum(); native.send(.smartZoom, phase: .none)
        case .zoomBegin: cancelScroll(); stopMomentum(); native.send(.zoom, phase: .began)
        case .zoom: native.send(.zoom, value: min(max(p.x, -0.95), 3), phase: .changed)
        case .zoomEnd: native.send(.zoom, phase: .ended)
        case .rotateBegin: cancelScroll(); stopMomentum(); native.send(.rotate, phase: .began)
        case .rotate: native.send(.rotate, value: min(max(p.x, -180), 180), phase: .changed)
        case .rotateEnd: native.send(.rotate, phase: .ended)
        case .swipe:
            if abs(p.x) > abs(p.y) { key(p.x > 0 ? 123 : 124, flags: .maskControl) }
            else { key(p.y < 0 ? 126 : 125, flags: .maskControl) }
        default: break
        }
    }
}
