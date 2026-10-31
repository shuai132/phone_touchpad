import SwiftUI
import Network

@main struct PhoneTouchpadApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var connection = Connection()
    @State private var host = ""
    @State private var code = ""
    @State private var showingScanner = false
    @State private var showingSettings = false
    @State private var forceAvailable = false
    @AppStorage("tapToClick") private var tapToClick = true
    @AppStorage("tapToDrag") private var tapToDrag = false
    @AppStorage("threeFingerDrag") private var threeFingerDrag = false
    @AppStorage("pressureToClick") private var pressureToClick = true
    @AppStorage("holdToClick") private var holdToClick = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Touchpad", systemImage: "computermouse").font(.title3.bold())
                Spacer()
                Text(connection.status).font(.caption).foregroundStyle(.secondary)
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("触控板设置")
                if connection.connected {
                    Button { connection.send(.reset); connection.disconnect() } label: { Image(systemName: "power") }
                        .accessibilityLabel("断开连接")
                }
            }.padding(.horizontal)
            if connection.connected {
                TouchSurface(threeFingerDrag: threeFingerDrag, tapToClick: tapToClick, tapToDrag: tapToDrag, active: !showingSettings && phase == .active, nativeTransforms: connection.nativeGestures, pressureToClick: pressureToClick, holdToClick: holdToClick) { kind, x, y, fingers, time in
                    connection.send(kind, x: x, y: y, fingers: fingers, at: time)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .bottom) {
                    Text(threeFingerDrag ? "单指移动 · 双指滚动 · 三指拖移" : "单指移动 · 双指滚动 · 三指切换空间")
                        .font(.caption).foregroundStyle(.secondary).padding().allowsHitTesting(false)
                }
                if !tapToClick {
                    HStack {
                        Button("左键") { connection.send(.click) }; Spacer()
                        Button("右键") { connection.send(.click, fingers: 2) }
                    }.buttonStyle(.bordered).padding(.horizontal)
                }
                if let latency = connection.latency {
                    Text("往返延迟 \(latency) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else {
                Form {
                    Section {
                        Button { showingScanner = true } label: {
                            Label("扫描 Mac 配对二维码", systemImage: "qrcode.viewfinder")
                        }
                        Text("在 Mac 启动 Touchpad Receiver，授权辅助功能后打开菜单栏二维码。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section(connection.discoveryStatus) {
                        if connection.macs.isEmpty { Text("确认手机和 Mac 已连接同一局域网。").foregroundStyle(.secondary) }
                        ForEach(connection.macs) { mac in
                            Button { connection.connect(endpoint: mac.endpoint, code: code) } label: {
                                Label(mac.name, systemImage: "desktopcomputer")
                            }.disabled((try? PairingSecret(text: code)) == nil)
                        }
                    }
                    Section {
                        DisclosureGroup("手动连接") {
                            TextField("Mac 局域网 IP 地址", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("Mac 配对密钥", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("连接 Mac") { connection.connect(host: host.trimmingCharacters(in: .whitespaces), code: code) }
                                .disabled(host.isEmpty || (try? PairingSecret(text: code)) == nil)
                            Text("粘贴 Mac 菜单栏复制的配对密钥，也可选择上方发现的设备。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
            }
        }.padding(.vertical, 8)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form {
                    Section("点按") {
                        Toggle("轻点来点按", isOn: $tapToClick)
                        Toggle("轻点后再次按住拖移", isOn: $tapToDrag).disabled(!tapToClick)
                        Text("启用拖移后，轻点一次，在同一位置附近再次按住或移动，抬指结束拖移。关闭轻点时，可使用触控板下方的左右键按钮。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("按压与拖移") {
                        Text(forceAvailable ? "当前设备支持真实 3D Touch 压力" : "当前设备未提供手指真实压感").font(.caption).foregroundStyle(.secondary)
                        Toggle("压力点击（需真实压感硬件）", isOn: $pressureToClick).disabled(!forceAvailable)
                        Toggle("长按模拟按压", isOn: $holdToClick)
                        Text("支持 3D Touch 的设备使用真实压力：加压按下，减压或抬指释放，按住移动可拖移。其他设备可开启长按模拟，单指停留约 0.35 秒后按下，抬指释放；这不是力度检测，也不是第二段 Force Click。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("多指") {
                        if connection.connected {
                            Text(connection.nativeGestures ? "双指捏合、旋转及双指双击智能缩放已连接（实验性）" : "此 Mac 未提供原生捏合与旋转支持").font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("三指拖移", isOn: $threeFingerDrag)
                        Text("关闭时三指滑动切换空间或打开调度中心；开启后使用四指滑动执行这些操作。Mac 的系统快捷键需要启用。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section { Text("指针速度、加速和自然滚动可在 Mac 菜单栏调整。").font(.caption).foregroundStyle(.secondary) }
                }.navigationTitle("触控板设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingSettings = false } } }
            }
        }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                PairingScanner { text in
                    guard let invitation = try? PairingInvitation(text: text) else { return }
                    code = invitation.secret.text; showingScanner = false
                    connection.connect(endpoint: .service(name: invitation.name, type: "_phonetouchpad._tcp", domain: "local.", interface: nil), code: code)
                }.ignoresSafeArea(edges: .bottom)
                .navigationTitle("扫描配对二维码").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingScanner = false } } }
            }
        }.onAppear {
            forceAvailable = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.traitCollection.forceTouchCapability == .available
        }.onChange(of: phase) { value in
            if value != .active { connection.send(.reset); connection.disconnect() }
            UIApplication.shared.isIdleTimerDisabled = value == .active && connection.connected
        }.onChange(of: connection.connected) { UIApplication.shared.isIdleTimerDisabled = $0 }
    }
}
