package dev.phonetouchpad.core

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class GestureParityTest {
    @Test fun matchesSwiftNativeTraces() {
        val stream = checkNotNull(javaClass.getResourceAsStream("/gestures.json"))
        val traces = JSONArray(stream.bufferedReader().use { it.readText() })
        for (index in 0 until traces.length()) {
            val trace = traces.getJSONObject(index)
            val name = trace.getString("name")
            val output = mutableListOf<Packet>()
            val engine = GestureEngine { output.add(it) }
            val options = trace.getJSONObject("options")
            engine.nativeTransforms = options.getBoolean("native")
            engine.tapToDrag = options.getBoolean("tapDrag")
            engine.tapToClick = options.getBoolean("tapClick")
            engine.threeFingerMode = if (options.getBoolean("threeDrag")) GestureEngine.ThreeFingerMode.DRAG else GestureEngine.ThreeFingerMode.SWIPE
            val steps = trace.getJSONArray("steps")
            for (i in 0 until steps.length()) {
                val step = steps.getJSONObject(i); val time = step.getDouble("time")
                when (step.getString("action")) {
                    "advance" -> engine.advance(time)
                    "cancel" -> engine.cancel(time)
                    else -> {
                        val points = step.getJSONArray("points")
                        engine.update((0 until points.length()).map { p -> val point = points.getJSONObject(p); TouchPoint(point.getInt("id"), point.getDouble("x"), point.getDouble("y")) }, time)
                    }
                }
            }
            val expected = trace.getJSONArray("expected")
            assertEquals(name, expected.length(), output.size)
            output.forEachIndexed { i, actual ->
                val packet = Packet.decode(expected.getJSONObject(i).toString())
                assertEquals("$name[$i]", packet.kind, actual.kind)
                assertEquals("$name[$i] fingers", packet.fingers, actual.fingers)
                assertEquals("$name[$i] version", packet.version, actual.version)
                assertEquals("$name[$i] x", packet.x, actual.x, 1e-7)
                assertEquals("$name[$i] y", packet.y, actual.y, 1e-7)
                assertEquals("$name[$i] time", packet.time!!, actual.time!!, 1e-9)
            }
        }
    }
    @Test fun rejectsInvalidKeysAndInvitations() {
        for (key in listOf("123456", "g".repeat(64), "é".repeat(64))) {
            try { pairingKey(key); fail("Invalid key accepted") } catch (_: IllegalArgumentException) {}
        }
        assertEquals(32, pairingKey("ab".repeat(32)).size)
        val invitation = Invitation.parse("phonetouchpad://pair?v=1&name=Mac%20%2B%20Work&key=${"ab".repeat(32)}")
        assertEquals("Mac + Work", invitation.name)
        try { Invitation.parse("phonetouchpad://pair?v=2&name=Mac&key=${"ab".repeat(32)}"); fail() } catch (_: IllegalArgumentException) {}
    }
}
