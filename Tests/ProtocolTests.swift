import XCTest
@testable import TouchpadCore
final class ProtocolTests: XCTestCase {
    func testFragmentedAndCombinedFrames() throws {
        let packet = InputPacket(kind: .move, x: 2.5, y: -4)
        let bytes = packet.framed()
        var buffer = PacketBuffer()
        XCTAssertTrue(try buffer.append(bytes.prefix(7)).isEmpty)
        let decoded = try buffer.append(bytes.dropFirst(7) + bytes)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].x, 2.5)
        XCTAssertEqual(decoded[1].y, -4)
    }
    func testOversizeAndMalformedFramesFail() {
        var buffer = PacketBuffer()
        XCTAssertThrowsError(try buffer.append(Data(repeating: 65, count: 65537)))
        var malformed = PacketBuffer()
        XCTAssertThrowsError(try malformed.append(Data("bad\n".utf8)))
    }
}
