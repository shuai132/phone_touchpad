package dev.phonetouchpad.android

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.*
import androidx.activity.ComponentActivity
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import dev.phonetouchpad.core.*

class MainActivity : ComponentActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val preferences by lazy { getSharedPreferences("touchpad", MODE_PRIVATE) }
    private val client = TouchpadClient({ main.post(it) }) { state -> update(state) }
    private lateinit var discovery: MacDiscovery
    private lateinit var status: TextView
    private lateinit var discoveryStatus: TextView
    private lateinit var devices: LinearLayout
    private var pad: TouchpadView? = null
    private var state = ClientState()
    private var host = ""
    private var key = ""
    private var hostField: EditText? = null
    private var keyField: EditText? = null
    private var pendingLink: String? = null
    private var names = emptyList<String>()
    private val scanner = registerForActivityResult(ScanContract()) { result -> result.contents?.let { invitation(it) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        discovery = MacDiscovery(this, { names = it; renderDevices() }, { if (::discoveryStatus.isInitialized) discoveryStatus.text = it })
        pendingLink = intent?.dataString
        render()
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); pendingLink = intent.dataString }
    override fun onStart() { super.onStart(); discovery.start() }
    override fun onResume() { super.onResume(); pendingLink?.let { pendingLink = null; invitation(it) } }
    override fun onPause() {
        rememberFields(); pad?.reset(); client.disconnect()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onPause()
    }
    override fun onStop() { discovery.stop(); super.onStop() }
    private fun rememberFields() { hostField?.let { host = it.text.toString() }; keyField?.let { key = it.text.toString() } }
    private fun text(value: String, size: Float = 14f) = TextView(this).apply { text = value; textSize = size; setTextColor(Color.DKGRAY); setPadding(dp(8), dp(8), dp(8), dp(8)) }
    private fun button(value: String, action: () -> Unit) = Button(this).apply { text = value; isAllCaps = false; setOnClickListener { action() } }
    private fun column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun render() {
        rememberFields(); pad?.reset(); pad = null; hostField = null; keyField = null
        val root = column().apply { setPadding(dp(12), dp(8), dp(12), dp(8)); setBackgroundColor(Color.WHITE) }
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        header.addView(text("Touchpad", 22f), LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(button("设置") { settings() })
        if (state.connected) header.addView(button("断开") { pad?.reset(); client.disconnect() })
        root.addView(header)
        status = text(state.status).apply { id = R.id.connection_status }; root.addView(status)
        if (state.connected) {
            val surface = TouchpadView(this) { client.send(it) }.apply { id = R.id.touchpad_surface }
            surface.engine.nativeTransforms = state.nativeTransforms
            surface.engine.tapToClick = preferences.getBoolean("tapToClick", true)
            surface.engine.tapToDrag = preferences.getBoolean("tapToDrag", false)
            surface.engine.holdToClick = preferences.getBoolean("holdToClick", false)
            surface.pressureClick = preferences.getBoolean("pressureClick", false)
            surface.engine.threeFingerMode = if (preferences.getBoolean("threeFingerDrag", false)) GestureEngine.ThreeFingerMode.DRAG else GestureEngine.ThreeFingerMode.SWIPE
            pad = surface
            root.addView(surface, LinearLayout.LayoutParams(-1, 0, 1f))
            if (!surface.engine.tapToClick) {
                val clicks = LinearLayout(this)
                clicks.addView(button("左键") { client.send(Packet("click")) }, LinearLayout.LayoutParams(0, -2, 1f))
                clicks.addView(button("右键") { client.send(Packet("click", fingers = 2)) }, LinearLayout.LayoutParams(0, -2, 1f))
                root.addView(clicks)
            }
        } else {
            val form = column()
            form.addView(button("扫描 Mac 配对二维码") { rememberFields(); scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt("扫描 Mac 菜单栏的配对二维码").setBeepEnabled(false).setOrientationLocked(false)) })
            form.addView(text("在 Mac 启动 Touchpad Receiver 并授权辅助功能，确认两端连接同一局域网。"))
            discoveryStatus = text("正在查找附近的 Mac…"); form.addView(discoveryStatus)
            devices = column(); form.addView(devices); renderDevices()
            hostField = EditText(this).apply { id = R.id.mac_host; hint = "Mac 局域网 IP 地址"; setText(host); inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI; isSingleLine = true }
            keyField = EditText(this).apply { id = R.id.pairing_key; hint = "Mac 配对密钥"; setText(key); inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; isSingleLine = true; importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS }
            form.addView(hostField); form.addView(keyField)
            form.addView(button("手动连接") { rememberFields(); client.connect(host.trim(), key = key) })
            val scroll = ScrollView(this); scroll.addView(form)
            root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        }
        setContentView(root)
    }
    private fun update(next: ClientState) {
        val changed = state.connected != next.connected
        state = next
        if (state.connected) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (changed) {
            if (next.connected) {
                currentFocus?.windowToken?.let { getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(it, 0) }
                currentFocus?.clearFocus()
            }
            render()
        }
        if (::status.isInitialized) status.text = next.status + (next.latencyMs?.let { " · 往返 ${it} ms" } ?: "")
    }
    private fun renderDevices() {
        if (!::devices.isInitialized || state.connected) return
        devices.removeAllViews()
        for (name in names) devices.addView(button(name) { rememberFields(); connectName(name) })
    }
    private fun connectName(name: String) {
        try { pairingKey(key) } catch (_: IllegalArgumentException) { status.text = "请先扫描二维码或输入完整配对密钥"; return }
        status.text = "正在解析 Mac 地址…"
        val secret = key
        discovery.resolve(name) { address, port ->
            if (address == null || port !in 1..65535) status.text = "无法解析 Mac，可手动输入局域网地址"
            else client.connect(address, port, secret)
        }
    }
    private fun invitation(value: String) {
        try {
            val invite = Invitation.parse(value); key = invite.key
            keyField?.setText(key)
            connectName(invite.name)
        } catch (_: Exception) { status.text = "不是有效的 Touchpad 配对二维码" }
    }
    private fun settings() {
        pad?.reset(); pad?.isEnabled = false
        val keys = arrayOf("tapToClick", "tapToDrag", "threeFingerDrag", "holdToClick", "pressureClick")
        val values = BooleanArray(keys.size) { preferences.getBoolean(keys[it], it == 0) }
        AlertDialog.Builder(this).setTitle("触控板设置")
            .setMultiChoiceItems(arrayOf("轻点来点按", "轻点后再次按住拖移（需开启轻点）", "三指拖移（关闭时三指切换空间）", "长按模拟按压：停留后按下，抬指释放", "压力变化点击（实验性估计，因机型而异）"), values) { dialog, which, checked ->
                values[which] = checked
                if (checked && (which == 3 || which == 4)) {
                    val other = if (which == 3) 4 else 3
                    values[other] = false; (dialog as AlertDialog).listView.setItemChecked(other, false)
                }
            }
            .setPositiveButton("完成") { _, _ -> keys.forEachIndexed { index, name -> preferences.edit().putBoolean(name, values[index]).apply() } }
            .setOnDismissListener { render() }.show()
    }
}
