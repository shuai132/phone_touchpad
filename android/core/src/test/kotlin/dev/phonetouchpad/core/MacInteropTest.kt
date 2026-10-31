package dev.phonetouchpad.core

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicInteger

class MacInteropTest {
    @Test fun connectsToActualSwiftReceiver() {
        val path = System.getProperty("touchpad.interop.file")
        assumeTrue("Run check-android-interop.sh for a live Swift receiver", path != null)
        val readyFile = File(path!!)
        val fixture = JSONObject(readyFile.readText())
        val port = fixture.getInt("port"); val key = fixture.getString("key")
        SecureChannel().use { owner ->
            owner.connect("127.0.0.1", port, key)
            owner.send(Packet("pair"))
            val pair = owner.receive()
            assertEquals("pair", pair.kind); assertEquals(PROTOCOL_VERSION, pair.version)
            assertEquals(true, pair.nativeGestures)
            owner.send(Packet("ping", time = 123.25))
            val pong = owner.receive()
            assertEquals("pong", pong.kind); assertEquals(123.25, pong.time!!, 0.0)
            SecureChannel().use { busy ->
                busy.connect("127.0.0.1", port, key); busy.send(Packet("pair"))
                assertEquals("receiverBusy", busy.receive().rejection)
            }
            SecureChannel().use { incompatible ->
                incompatible.connect("127.0.0.1", port, key); incompatible.send(Packet("pair", version = 99))
                assertEquals("incompatibleVersion", incompatible.receive().rejection)
            }
            owner.send(Packet("ping", time = 124.0)); assertEquals("pong", owner.receive().kind)
            owner.send(Packet("contact")); owner.send(Packet("down")); owner.send(Packet("move", x = 12.0, time = 1.0)); owner.send(Packet("up"))
            owner.send(Packet("zoomBegin")); owner.send(Packet("zoom", x = 0.125)); owner.send(Packet("zoomEnd"))
            owner.send(Packet("scrollBegin")); owner.send(Packet("scroll", y = 12.0, time = 2.0)); owner.send(Packet("scrollEnd", time = 2.01))
            owner.send(Packet("reset"))
        }
        fun await(message: String, condition: () -> Boolean) {
            val deadline = System.nanoTime() + 12_000_000_000L
            while (!condition()) { check(System.nanoTime() < deadline) { message }; Thread.sleep(10) }
        }
        await("Swift owner did not close") { File(readyFile.parentFile, "idle").exists() }
        var acceptedWrongKey = false
        SecureChannel().use { bad ->
            val wrong = (if (key[0] == '0') "1" else "0") + key.drop(1)
            try { bad.connect("127.0.0.1", port, wrong); acceptedWrongKey = true } catch (_: Exception) {}
        }
        assertFalse("Wrong PSK was accepted", acceptedWrongKey)
        val state = AtomicReference(ClientState())
        val latencyUpdates = AtomicInteger()
        val client = TouchpadClient({ it() }) { next -> state.set(next); if (next.latencyMs != null) latencyUpdates.incrementAndGet() }
        try {
            client.connect("127.0.0.1", port, key)
            await("Production Kotlin client did not pair and receive heartbeat") { state.get().connected && state.get().latencyMs != null }
            assertTrue(state.get().nativeTransforms)
            val blocked = AtomicReference(ClientState())
            val contender = TouchpadClient({ it() }) { blocked.set(it) }
            try {
                contender.connect("127.0.0.1", port, key)
                await("Kotlin client did not display busy reason") { blocked.get().status == rejectionMessage("receiverBusy") }
                assertFalse(blocked.get().connected); assertTrue(state.get().connected)
            } finally { contender.disconnect() }
            val before = latencyUpdates.get()
            client.send(Packet("down")); client.send(Packet("move", x = 6.0, time = 3.0))
            await("Queued input did not reach next heartbeat") { latencyUpdates.get() > before }
            File(readyFile.parentFile, "drop").writeText("drop")
            await("Production Kotlin client did not detect receiver disconnect") { !state.get().connected }
            assertTrue(state.get().status.contains("连接中断"))
            assertFalse(state.get().nativeTransforms); assertNull(state.get().latencyMs)
        } finally { client.disconnect() }
        File(readyFile.parentFile, "done").writeText("done")
    }
}
