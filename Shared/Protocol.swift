import Foundation

struct InputPacket: Codable {
    static let currentVersion = 1
    enum Kind: String, Codable { case pair, rejected, ping, pong, contact, move, click, down, up, scrollBegin, scroll, scrollEnd, swipe, zoomBegin, zoom, zoomEnd, rotateBegin, rotate, rotateEnd, smartZoom, reset }
    var kind: Kind
    var x: Double = 0
    var y: Double = 0
    var fingers: Int = 1
    var time: Double? = nil
    var nativeGestures: Bool? = nil
    var version: Int? = InputPacket.currentVersion
    var rejection: PairingRejection? = nil
}

// Newline framing survives TCP fragmentation and multiple messages per read.
struct PacketBuffer {
    private var data = Data()
    mutating func append(_ chunk: Data) throws -> [InputPacket] {
        data.append(chunk)
        guard data.count <= 65536 else { throw CocoaError(.fileReadTooLarge) }
        var packets: [InputPacket] = []
        while let index = data.firstIndex(of: 10) {
            let line = data[..<index]
            data.removeSubrange(...index)
            packets.append(try JSONDecoder().decode(InputPacket.self, from: line))
        }
        return packets
    }
}
extension InputPacket {
    func framed() -> Data {
        var bytes = try! JSONEncoder().encode(self)
        bytes.append(10)
        return bytes
    }
}

enum PairingRejection: String, Codable {
    case receiverBusy, accessibilityRequired, incompatibleVersion, pairingRequired
    var message: String {
        switch self {
        case .receiverBusy: return "此 Mac 已有连接，请先断开现有连接或稍后重试"
        case .accessibilityRequired: return "请在 Mac 菜单栏授权辅助功能，然后重新连接"
        case .incompatibleVersion: return "两端协议版本不兼容，请更新手机和 Mac 应用"
        case .pairingRequired: return "尚未完成配对，请重新连接"
        }
    }
}
