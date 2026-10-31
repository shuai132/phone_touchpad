import Foundation
import Network

@MainActor final class ReplyPeer {
    let connection: NWConnection
    var packet: InputPacket?
    private var buffer = PacketBuffer()
    init(endpoint: NWEndpoint, secret: PairingSecret) {
        connection = NWConnection(to: endpoint, using: SecureTransport.parameters(secret: secret))
        connection.start(queue: .main)
    }
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, let frames = try? self.buffer.append(data), let first = frames.first { self.packet = first }
                if self.packet == nil && !done && error == nil { self.receive() }
            }
        }
    }
}

@main struct PairingRejectionCheck {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "PairingRejectionCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, message)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("Pairing rejection check failed: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        let suite = "dev.phonetouchpad.pairing-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var eventCount = 0
        // Injecting an authorization result does not request or change OS permissions.
        // Every generated input event is captured; none is posted to the system.
        let receiver = Receiver(port: .any, advertise: false, preferences: preferences, permissionCheck: { true }, postEvent: { _ in eventCount += 1 })
        defer { receiver.stop() }
        try await wait("Receiver listener failed") { receiver.boundPort != nil }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: receiver.boundPort!)
        let owner = Connection(discover: false)
        defer { owner.disconnect() }
        owner.connect(endpoint: endpoint, code: receiver.code)
        try await wait("Owner did not pair") { owner.connected && receiver.connected }
        let contender = Connection(discover: false)
        defer { contender.disconnect() }
        contender.connect(endpoint: endpoint, code: receiver.code)
        try await wait("Busy rejection not displayed") { contender.status == PairingRejection.receiverBusy.message }
        try require(!contender.connected && owner.connected && receiver.connected, "Contender displaced existing owner")
        try require(receiver.status == "手机已连接", "Rejected contender changed owner's status")
        contender.send(.click)
        try await Task.sleep(nanoseconds: 50_000_000)
        try require(eventCount == 0, "Rejected contender generated input")

        func rejection(for packet: InputPacket) async throws -> InputPacket {
            let peer = ReplyPeer(endpoint: endpoint, secret: try PairingSecret(text: receiver.code))
            defer { peer.connection.cancel() }
            try await wait("Reply peer TLS failed") { if case .ready = peer.connection.state { return true }; return false }
            peer.receive()
            peer.connection.send(content: packet.framed(), completion: .contentProcessed { _ in })
            try await wait("No rejection received") { peer.packet != nil }
            return peer.packet!
        }
        let incompatible = try await rejection(for: InputPacket(kind: .pair, version: 99))
        try require(incompatible.kind == .rejected && incompatible.rejection == .incompatibleVersion && incompatible.version == InputPacket.currentVersion, "Wrong version response")
        let legacy = try await rejection(for: InputPacket(kind: .pair, version: nil))
        try require(legacy.rejection == .incompatibleVersion, "Unversioned packet accepted")
        let earlyInput = try await rejection(for: InputPacket(kind: .down))
        try require(earlyInput.rejection == .pairingRequired && eventCount == 0, "Unpaired input accepted")
        try require(owner.connected && receiver.connected, "Invalid peer affected valid session")
        owner.disconnect()
        try await wait("Owner did not release session") { !receiver.connected }
        contender.connect(endpoint: endpoint, code: receiver.code)
        try await wait("Contender could not connect after owner left") { contender.connected && receiver.connected }
        contender.disconnect()

        let denied = Receiver(port: .any, advertise: false, preferences: preferences, permissionCheck: { false }, postEvent: { _ in eventCount += 1 })
        defer { denied.stop() }
        try await wait("Denied receiver did not start") { denied.boundPort != nil }
        let deniedClient = Connection(discover: false)
        defer { deniedClient.disconnect() }
        deniedClient.connect(endpoint: .hostPort(host: "127.0.0.1", port: denied.boundPort!), code: denied.code)
        try await wait("Permission rejection not displayed") { deniedClient.status == PairingRejection.accessibilityRequired.message }
        try await Task.sleep(nanoseconds: 50_000_000)
        try require(deniedClient.status == PairingRejection.accessibilityRequired.message && !deniedClient.connected && !denied.connected, "Connection close overwrote rejection")
        try require(eventCount == 0, "Denied session generated input")
        print("Busy owner protection, explicit rejection, protocol versions, unpaired input and permission denial checks passed")
    }
}
