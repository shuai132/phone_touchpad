package dev.phonetouchpad.core

import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class ClientState(val connected: Boolean = false, val status: String = "未连接", val nativeTransforms: Boolean = false, val latencyMs: Long? = null)

class TouchpadClient(private val dispatch: (() -> Unit) -> Unit, private val onState: (ClientState) -> Unit) {
    private val lock = Any()
    private var current: Session? = null
    private var generation = 0L
    fun connect(host: String, port: Int = RECEIVER_PORT, key: String) {
        disconnect()
        val token: Long
        val session: Session
        synchronized(lock) {
            token = ++generation
            try { pairingKey(key) } catch (e: IllegalArgumentException) { publish(token, ClientState(status = e.message ?: "配对密钥无效")); return }
            session = Session(token, host, port, key)
            current = session
            publish(token, ClientState(status = "正在连接…"))
        }
        session.start()
    }
    fun send(packet: Packet) { synchronized(lock) { current }?.let { if (it.paired.get()) it.enqueue(packet) } }
    fun disconnect() {
        synchronized(lock) {
            generation++; val old = current; current = null; old?.close()
            publish(generation, ClientState())
        }
    }
    private fun publish(token: Long, state: ClientState) {
        dispatch {
            synchronized(lock) {
                if (generation == token && (!state.connected || (current?.token == token && current?.paired?.get() == true))) onState(state)
            }
        }
    }
    private inner class Session(val token: Long, val host: String, val port: Int, val key: String) {
        val paired = AtomicBoolean(false)
        private val active = AtomicBoolean(true)
        private val channel = SecureChannel()
        private val writer = Executors.newSingleThreadExecutor { r -> Thread(r, "touchpad-writer").apply { isDaemon = true } }
        private val heartbeat = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "touchpad-heartbeat").apply { isDaemon = true } }
        private val lastPong = AtomicLong(System.nanoTime())
        private var native = false
        fun start() {
            Thread({
                try {
                    channel.connect(host, port, key)
                    if (!active.get()) return@Thread
                    channel.send(Packet("pair"))
                    while (active.get()) {
                        val packet = channel.receive()
                        if (packet.version != PROTOCOL_VERSION) { fail(rejectionMessage("incompatibleVersion")); break }
                        when (packet.kind) {
                            "rejected" -> { fail(rejectionMessage(packet.rejection)); break }
                            "pair" -> if (paired.compareAndSet(false, true)) {
                                native = packet.nativeGestures == true
                                lastPong.set(System.nanoTime())
                                publish(token, ClientState(true, "已连接", native))
                                if (active.get()) heartbeat.scheduleAtFixedRate({
                                    if (System.nanoTime() - lastPong.get() > TimeUnit.SECONDS.toNanos(5)) fail("连接中断，请重新连接")
                                    else enqueue(Packet("ping", time = System.nanoTime() / 1e9))
                                }, 0, 1, TimeUnit.SECONDS)
                            }
                            "pong" -> if (paired.get()) {
                                val now = System.nanoTime(); lastPong.set(now)
                                val latency = packet.time?.takeIf { it.isFinite() }?.let { ((now / 1e9 - it) * 1000).coerceIn(0.0, 60000.0).toLong() }
                                publish(token, ClientState(true, "已连接", native, latency))
                            }
                        }
                    }
                } catch (_: Exception) { fail(if (paired.get()) "连接中断，请重新连接" else "连接或加密握手失败，请检查地址并重新扫描二维码") }
                finally { close() }
            }, "touchpad-reader").apply { isDaemon = true; start() }
        }
        fun enqueue(packet: Packet) {
            if (!active.get()) return
            try { writer.execute {
                if (active.get()) try { channel.send(packet) } catch (_: Exception) { fail("连接中断，请重新连接") }
            } } catch (_: RejectedExecutionException) { /* Session was closed concurrently. */ }
        }
        private fun fail(message: String) {
            synchronized(lock) {
                if (current !== this) return
                current = null; close(); publish(token, ClientState(status = message))
            }
        }
        fun close() {
            if (active.compareAndSet(true, false)) {
                paired.set(false); channel.close(); writer.shutdownNow(); heartbeat.shutdownNow()
            }
        }
    }
}
