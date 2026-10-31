import Foundation
@main struct ProtocolCheck {
    static func main() throws {
        let packet = InputPacket(kind: .move, x: 2.5, y: -4)
        let bytes = packet.framed()
        var buffer = PacketBuffer()
        let partial = try buffer.append(bytes.prefix(7))
        precondition(partial.isEmpty)
        let packets = try buffer.append(bytes.dropFirst(7) + bytes)
        precondition(packets.count == 2 && packets[0].x == 2.5 && packets[1].y == -4)
        var oversized = PacketBuffer()
        do { _ = try oversized.append(Data(repeating: 65, count: 65537)); fatalError("Expected rejection") } catch {}
        var malformed = PacketBuffer()
        do { _ = try malformed.append(Data("bad\n".utf8)); fatalError("Expected rejection") } catch {}
        print("Protocol checks passed")
    }
}
