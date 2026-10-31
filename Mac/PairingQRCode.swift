import SwiftUI
import CoreImage.CIFilterBuiltins

enum PairingQRCodeRenderer {
    private static let context = CIContext()
    static func image(text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}

struct PairingQRCode: View {
    let text: String
    var body: some View {
        if let image = PairingQRCodeRenderer.image(text: text) {
            Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: 220, height: 220).padding(16).background(.white)
                .accessibilityLabel("配对二维码，使用手机 Touchpad 扫描")
        } else { Text("二维码生成失败，可复制配对密钥") }
    }
}
