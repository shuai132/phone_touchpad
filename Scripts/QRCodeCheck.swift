import Foundation
import CoreImage

@main struct QRCodeCheck {
    static func main() throws {
        let invitation = PairingInvitation(name: "我的 Mac-123456", secret: try PairingSecret(text: String(repeating: "ab", count: 32)))
        let payload = invitation.url.absoluteString
        guard let image = PairingQRCodeRenderer.image(text: payload) else { fatalError("QR rendering failed") }
        let qr = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let extent = qr.extent.insetBy(dx: -24, dy: -24)
        let background = CIImage(color: .white).cropped(to: extent)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let decoded = detector.features(in: qr.composited(over: background)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        precondition(decoded == [payload])
        print("Rendered pairing QR round-trip check passed")
    }
}
