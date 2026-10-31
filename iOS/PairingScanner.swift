import SwiftUI
import AVFoundation
import UIKit

struct PairingScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController(); controller.onScan = onScan; return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "touchpad.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private let message = UILabel()
    private var requested = false
    private var visible = false
    private var delivered = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview); self.preview = preview
        message.text = "将镜头对准 Mac 菜单栏中的配对二维码"
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.addSubview(message)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        message.frame = CGRect(x: 16, y: view.safeAreaInsets.top + 16, width: view.bounds.width - 32, height: 90)
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            switch orientation {
            case .landscapeLeft: preview?.connection?.videoOrientation = .landscapeLeft
            case .landscapeRight: preview?.connection?.videoOrientation = .landscapeRight
            case .portraitUpsideDown: preview?.connection?.videoOrientation = .portraitUpsideDown
            default: preview?.connection?.videoOrientation = .portrait
            }
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); visible = true
        guard !requested else { return }; requested = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.visible else { return }
                if allowed { self.configure() }
                else { self.message.text = "请在系统设置中允许相机权限，或关闭后手动输入配对密钥。" }
            }
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stop() }
    func stop() {
        visible = false
        captureQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }
    private func configure() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let camera = AVCaptureDevice.default(for: .video) else { throw ScannerError.unavailable }
                let input = try AVCaptureDeviceInput(device: camera)
                let output = AVCaptureMetadataOutput()
                self.session.beginConfiguration()
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                    self.session.commitConfiguration(); throw ScannerError.unavailable
                }
                self.session.addInput(input); self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                self.session.commitConfiguration(); self.session.startRunning()
            } catch {
                DispatchQueue.main.async { self.message.text = "相机无法启动，请关闭后手动输入配对密钥。" }
            }
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible, !delivered,
              let text = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        guard (try? PairingInvitation(text: text)) != nil else {
            message.text = "这不是有效的 Touchpad 配对二维码"; return
        }
        delivered = true; stop(); onScan?(text)
    }
    private enum ScannerError: Error { case unavailable }
}
