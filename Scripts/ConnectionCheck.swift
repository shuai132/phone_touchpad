import Foundation
import Network
import Security

/// Exercises the actual client against a local TCP peer, without Accessibility or Bonjour permissions.
@MainActor final class TestPeer {
    let listener: NWListener
    var connection: NWConnection?
    var respond = true
    var sawMove = false
    var pairCount = 0
    var tlsVerified = false
    init() throws {
        listener = try NWListener(using: SecureTransport.parameters(secret: PairingSecret(text: String(repeating: "ab", count: 32))), on: .any)
        listener.newConnectionHandler = { [weak self] c in
            Task { @MainActor [c] in
            guard let self else { return }
            self.connection = c
            c.stateUpdateHandler = { [weak self, weak c] state in
                Task { @MainActor in
                    guard case .ready = state, let c,
                          let metadata = c.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return }
                    let security = metadata.securityProtocolMetadata
                    self?.tlsVerified = sec_protocol_metadata_get_negotiated_tls_protocol_version(security) == .TLSv12 && sec_protocol_metadata_get_negotiated_tls_ciphersuite(security).rawValue == 0x00A8
                }
            }
            c.start(queue: .main)
            self.receive(c, buffer: PacketBuffer())
            }
        }
    }
    func receive(_ c: NWConnection, buffer: PacketBuffer) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            Task { @MainActor in
            guard let self else { return }
            var buffer = buffer
            if let data, let packets = try? buffer.append(data) {
                for var packet in packets {
                    if packet.kind == .pair { self.pairCount += 1 }
                    if packet.kind == .move { self.sawMove = packet.time == 123 && packet.x == 3 }
                    if self.respond && (packet.kind == .pair || packet.kind == .ping) {
                        if packet.kind == .ping { packet.kind = .pong }
                        if packet.kind == .pair { packet.nativeGestures = true }
                        c.send(content: packet.framed(), completion: .contentProcessed { _ in })
                    }
                }
            }
            if !done && error == nil { self.receive(c, buffer: buffer) }
            }
        }
    }
    func stop() { connection?.cancel(); listener.cancel() }
}

@main struct ConnectionCheck {
    @MainActor static func main() async throws {
        let peer = try TestPeer()
        defer { peer.stop() }
        peer.listener.start(queue: .main)
        try await wait { if case .ready = peer.listener.state { return true }; return false }
        let client = Connection(discover: false)
        client.connect(endpoint: .hostPort(host: "127.0.0.1", port: peer.listener.port!), code: String(repeating: "ab", count: 32))
        try await wait { client.connected }
        precondition(client.nativeGestures)
        try await wait { client.latency != nil }
        client.send(.move, x: 3, at: 123)
        try await wait { peer.sawMove }
        precondition(peer.tlsVerified)
        let wrongKeyClient = Connection(discover: false)
        wrongKeyClient.connect(endpoint: .hostPort(host: "127.0.0.1", port: peer.listener.port!), code: String(repeating: "cd", count: 32))
        try await wait(seconds: 12) { wrongKeyClient.status != "正在连接…" }
        precondition(!wrongKeyClient.connected && peer.pairCount == 1)
        wrongKeyClient.disconnect()
        let plaintext = NWConnection(host: "127.0.0.1", port: peer.listener.port!, using: .tcp)
        plaintext.start(queue: .main)
        try await wait { if case .ready = plaintext.state { return true }; return false }
        plaintext.send(content: InputPacket(kind: .pair).framed(), completion: .contentProcessed { _ in })
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(peer.pairCount == 1)
        plaintext.cancel()
        peer.respond = false
        try await wait(seconds: 8) { !client.connected }
        precondition(client.status.contains("连接中断"))
        precondition(client.latency == nil && !client.nativeGestures)
        print("TLS pairing, negotiated cipher, wrong-key/plaintext rejection, heartbeat and lost-peer checks passed")
    }
    @MainActor static func wait(seconds: Double = 3, until condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition() {
            precondition(ProcessInfo.processInfo.systemUptime < deadline, "Timed out")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
