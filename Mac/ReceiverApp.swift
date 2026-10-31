import SwiftUI
import AppKit

final class ReceiverLifecycle: NSObject, NSApplicationDelegate {
    let receiver = Receiver()
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak receiver] _ in receiver?.disconnectDevice() })
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll(); receiver.stop()
    }
}

@main struct ReceiverApp: App {
    @NSApplicationDelegateAdaptor(ReceiverLifecycle.self) private var lifecycle
    var body: some Scene {
        MenuBarExtra("Touchpad", systemImage: "computermouse") { ReceiverMenu(receiver: lifecycle.receiver) }
            .menuBarExtraStyle(.window)
    }
}

struct ReceiverMenu: View {
    @ObservedObject var receiver: Receiver
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PairingQRCode(text: receiver.invitation)
            Button("复制配对密钥") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(receiver.code, forType: .string)
            }
            Text(receiver.status)
            Text(NativeGestures.supported ? "原生缩放 / 旋转：实验性支持" : "此系统不支持原生缩放 / 旋转").font(.caption).foregroundStyle(.secondary)
            Text("用手机 Touchpad 扫描二维码连接").font(.caption)
            Text("指针速度")
            Slider(value: $receiver.pointerSpeed, in: 0.25...3)
            Toggle("指针加速", isOn: $receiver.pointerAcceleration)
            Toggle("自然滚动", isOn: $receiver.naturalScrolling)
            Button("授权辅助功能") { receiver.authorize() }
            Button("断开并更换密钥") { receiver.rotateCode() }
            Divider()
            Button("退出") { receiver.stop(); NSApplication.shared.terminate(nil) }
        }.padding().frame(width: 300)
    }
}
