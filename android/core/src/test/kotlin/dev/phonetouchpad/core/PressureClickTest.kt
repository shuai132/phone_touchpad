package dev.phonetouchpad.core

import org.junit.Assert.*
import org.junit.Test

class PressureClickTest {
    @Test fun constantDevicePressureNeverMeansFirmPress() {
        val estimate = PressureEstimate()
        repeat(100) { assertEquals(0.0, estimate.sample(1.0)!!, 0.0) }
        assertEquals(0.6, estimate.sample(1.6)!!, 1e-9)
        assertEquals(0.2, estimate.sample(1.2)!!, 1e-9)
        assertEquals(1.0, estimate.sample(1.0, deepPress = true)!!, 0.0)
        assertNull(estimate.sample(Double.NaN)); assertNull(estimate.sample(-1.0))
    }
    @Test fun pressurePressUsesHysteresisAndNeverAddsTap() {
        val packets = mutableListOf<Packet>()
        val engine = GestureEngine { packets.add(it) }
        fun feed(t: Double, force: Double, x: Double = 0.0) = engine.update(listOf(TouchPoint(1, x, 0.0, force)), t)
        feed(0.0, 0.1); feed(0.1, 0.6); feed(0.12, 0.5); feed(0.2, 0.7, 12.0); feed(0.3, 0.3, 12.0); engine.update(emptyList(), 0.4)
        assertEquals(listOf("contact", "down", "move", "up"), packets.map { it.kind })
    }
    @Test fun holdFallbackReleasesWithoutTapToClick() {
        val packets = mutableListOf<Packet>()
        val engine = GestureEngine { packets.add(it) }.apply { holdToClick = true; tapToClick = false }
        engine.update(listOf(TouchPoint(1, 0.0, 0.0)), 0.0)
        engine.advance(0.34); assertEquals(listOf("contact"), packets.map { it.kind })
        engine.advance(0.36); engine.advance(0.5)
        engine.update(listOf(TouchPoint(1, 15.0, 0.0)), 0.6)
        engine.update(emptyList(), 0.7)
        assertEquals(listOf("contact", "down", "move", "up"), packets.map { it.kind })
        assertFalse(engine.needsClock)
    }
}
