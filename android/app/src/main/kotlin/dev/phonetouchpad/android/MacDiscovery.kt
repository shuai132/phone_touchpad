package dev.phonetouchpad.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper

class MacDiscovery(context: Context, private val changed: (List<String>) -> Unit, private val status: (String) -> Unit) {
    private val manager = context.getSystemService(NsdManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val names = linkedSetOf<String>()
    private var listener: NsdManager.DiscoveryListener? = null
    private var generation = 0
    private var resolving = false
    private data class Request(val name: String, val done: (String?, Int) -> Unit)
    private val pending = ArrayDeque<Request>()
    fun start() {
        if (listener != null) return
        val token = generation
        listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) { main.post { if (token == generation) status("选择附近的 Mac，或扫描二维码") } }
            override fun onServiceFound(info: NsdServiceInfo) { main.post { if (token == generation) { names.add(info.serviceName); changed(names.sorted()) } } }
            override fun onServiceLost(info: NsdServiceInfo) { main.post { if (token == generation) { names.remove(info.serviceName); changed(names.sorted()) } } }
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) { main.post { if (token == generation) status("无法发现 Mac，可使用手动地址连接") } }
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
        }
        try { manager.discoverServices("_phonetouchpad._tcp.", NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (_: Exception) { listener = null; status("无法发现 Mac，请检查网络权限") }
        next()
    }
    fun stop() {
        generation++; listener?.let { try { manager.stopServiceDiscovery(it) } catch (_: Exception) {} }
        listener = null; pending.clear(); names.clear(); changed(emptyList())
    }
    fun resolve(name: String, done: (String?, Int) -> Unit) { pending.add(Request(name, done)); next() }
    private fun next() {
        if (listener == null || resolving || pending.isEmpty()) return
        val request = pending.removeFirst(); resolving = true
        val token = generation
        val info = NsdServiceInfo().apply { serviceName = request.name; serviceType = "_phonetouchpad._tcp." }
        try {
            manager.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(service: NsdServiceInfo, code: Int) { main.post { resolving = false; if (token == generation) request.done(null, 0); next() } }
                override fun onServiceResolved(service: NsdServiceInfo) { main.post { resolving = false; if (token == generation) request.done(service.host?.hostAddress, service.port); next() } }
            })
        } catch (_: Exception) { resolving = false; request.done(null, 0); next() }
    }
}
