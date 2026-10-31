import Foundation
import Network
import Combine

@MainActor final class Connection: ObservableObject {
    @Published var status = "未连接"
    @Published var connected = false
    @Published var latency: Int?
    @Published var nativeGestures = false
    private var heartbeat: Task<Void, Never>?
    private var pairingDeadline: Task<Void, Never>?
    private var lastPong = 0.0
    private func startHeartbeat() {
        heartbeat?.cancel()
        lastPong = ProcessInfo.processInfo.systemUptime
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.connected else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastPong > 5 {
                    self.disconnect(); self.status = "连接中断，请重新连接"; return
                }
                self.send(.ping)
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }
    struct DiscoveredMac: Identifiable {
        var id: String
        var name: String
        var endpoint: NWEndpoint
    }
    @Published var macs: [DiscoveredMac] = []
    @Published var discoveryStatus = "正在查找附近的 Mac…"
    private var browser: NWBrowser?
    private var connection: NWConnection?
    init(discover: Bool = true) {
        guard discover else { return }
        let browser = NWBrowser(for: .bonjour(type: "_phonetouchpad._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.macs = results.compactMap { result in
                    guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                    return DiscoveredMac(id: "\(name).\(type).\(domain)", name: name, endpoint: result.endpoint)
                }.sorted { $0.name < $1.name }
                self?.discoveryStatus = results.isEmpty ? "未发现 Mac，可手动输入地址" : "选择附近的 Mac"
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.discoveryStatus = "无法发现设备，请检查本地网络权限" } }
        }
        browser.start(queue: .main)
    }
    private var buffer = PacketBuffer()
    func connect(host: String, code: String) {
        connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: BonjourPort), code: code)
    }
    func connect(endpoint: NWEndpoint, code: String) {
        disconnect()
        guard let secret = try? PairingSecret(text: code) else { status = "请扫描 Mac 二维码或输入完整配对密钥"; return }
        let c = NWConnection(to: endpoint, using: SecureTransport.parameters(secret: secret))
        connection = c
        status = "正在连接…"
        c.stateUpdateHandler = { [weak self, weak c] state in
            Task { @MainActor in
                guard let self, let c, self.connection === c else { return }
                switch state {
                case .ready:
                    guard SecureTransport.isAuthenticatedPSK(c) else {
                        self.disconnect(); self.status = "加密握手验证失败"; return
                    }
                    self.send(.pair); self.receive(c)
                case .failed(let error):
                    self.disconnect()
                    if case .tls = error { self.status = "加密连接失败，请重新扫描 Mac 二维码" }
                    else { self.status = "连接失败，请检查地址和网络" }
                default: break
                }
            }
        }
        c.start(queue: .main)
        pairingDeadline = Task { @MainActor [weak self, weak c] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, let c, self.connection === c, !self.connected else { return }
            self.disconnect(); self.status = "配对超时，请检查 Mac 授权和配对密钥"
        }
    }
    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                do {
                    if let data {
                        for packet in try self.buffer.append(data) {
                            guard packet.version == InputPacket.currentVersion else {
                                self.disconnect(); self.status = PairingRejection.incompatibleVersion.message; return
                            }
                            if packet.kind == .rejected {
                                self.disconnect(); self.status = packet.rejection?.message ?? "Mac 拒绝了连接，请重新配对"; return
                            }
                            if packet.kind == .pair && !self.connected {
                                self.pairingDeadline?.cancel(); self.pairingDeadline = nil
                                self.nativeGestures = packet.nativeGestures == true
                                self.connected = true; self.status = "已连接"; self.startHeartbeat()
                            } else if packet.kind == .pong {
                                self.lastPong = ProcessInfo.processInfo.systemUptime
                                if let sent = packet.time, sent.isFinite {
                                    self.latency = Int(min(max((self.lastPong - sent) * 1000, 0), 60000))
                                }
                            }
                        }
                    }
                    if done || error != nil {
                        let message = self.connected ? "连接已断开，请重新连接" : "配对未完成，请检查 Mac 授权与密钥"
                        self.disconnect(); self.status = message
                    } else { self.receive(c) }
                } catch { self.disconnect(); self.status = "收到无效连接数据，请更新两端应用后重试" }
            }
        }
    }
    func send(_ kind: InputPacket.Kind, x: Double = 0, y: Double = 0, fingers: Int = 1, at sampleTime: Double? = nil) {
        let time = sampleTime ?? ProcessInfo.processInfo.systemUptime
        guard x.isFinite, y.isFinite, time.isFinite else { return }
        connection?.send(content: InputPacket(kind: kind, x: x, y: y, fingers: fingers, time: time).framed(), completion: .contentProcessed { _ in })
    }
    func disconnect() {
        pairingDeadline?.cancel(); pairingDeadline = nil
        heartbeat?.cancel(); heartbeat = nil; latency = nil; nativeGestures = false
        connection?.cancel(); connection = nil; connected = false; buffer = PacketBuffer(); status = "未连接"
    }
}
private let BonjourPort = NWEndpoint.Port(rawValue: 49271)!
