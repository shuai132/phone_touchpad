package dev.phonetouchpad.android

import android.graphics.Bitmap
import android.app.UiAutomation
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.*
import androidx.test.espresso.matcher.ViewMatchers.*
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.phonetouchpad.core.GestureEngine
import dev.phonetouchpad.core.Packet
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.hypot

@RunWith(AndroidJUnit4::class)
class DeviceFlowTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    @Before fun resetSettings() {
        instrumentation.targetContext.getSharedPreferences("touchpad", 0).edit().clear().commit()
    }
    private fun await(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 15000
        while (!condition()) { check(SystemClock.uptimeMillis() < deadline) { message }; SystemClock.sleep(20) }
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        File(instrumentation.targetContext.filesDir, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
    @Test fun startsAndPersistsSettings() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            onView(withText("设置")).perform(click())
            onView(withText("轻点来点按")).perform(click())
            onView(withText("完成")).perform(click())
            scenario.onActivity { assertFalse(it.getSharedPreferences("touchpad", 0).getBoolean("tapToClick", true)) }
            onView(withText("扫描 Mac 配对二维码")).check(androidx.test.espresso.assertion.ViewAssertions.matches(isDisplayed()))
            capture("connect.png")
        }
    }
    private data class P(val id: Int, val x: Float, val y: Float, val pressure: Float = 1f)
    private fun event(action: Int, points: List<P>, downTime: Long): MotionEvent {
        val properties = points.map { MotionEvent.PointerProperties().apply { id = it.id; toolType = MotionEvent.TOOL_TYPE_FINGER } }.toTypedArray()
        val coordinates = points.map { MotionEvent.PointerCoords().apply { x = it.x; y = it.y; pressure = it.pressure; size = 0.1f } }.toTypedArray()
        return MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, points.size, properties, coordinates, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
    }
    @Test fun nativeViewReplaysHistoryAndStaggeredLifts() {
        val packets = CopyOnWriteArrayList<Packet>()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val view = AtomicReference<TouchpadView>()
            scenario.onActivity { activity ->
                view.set(TouchpadView(activity) { packets.add(it) })
                activity.setContentView(view.get())
            }
            val density = instrumentation.targetContext.resources.displayMetrics.density
            val down = SystemClock.uptimeMillis()
            fun local(action: Int, points: List<P>) {
                val e = event(action, points.map { P(it.id, it.x * density, it.y * density, it.pressure) }, down)
                scenario.onActivity { view.get().dispatchTouchEvent(e) }; e.recycle()
            }
            local(MotionEvent.ACTION_DOWN, listOf(P(1, 100f, 100f)))
            val batch = event(MotionEvent.ACTION_MOVE, listOf(P(1, 110f * density, 110f * density)), down)
            SystemClock.sleep(20)
            batch.addBatch(SystemClock.uptimeMillis(), arrayOf(MotionEvent.PointerCoords().apply { x = 120f * density; y = 100f * density; pressure = 1f; size = 0.1f }), 0)
            scenario.onActivity { view.get().dispatchTouchEvent(batch) }; batch.recycle()
            local(MotionEvent.ACTION_UP, listOf(P(1, 120f, 100f)))
            assertTrue(packets.filter { it.kind == "move" }.sumOf { hypot(it.x, it.y) } > 25)
            assertFalse(packets.any { it.kind == "click" })
            scenario.onActivity { view.get().reset(); view.get().engine.nativeTransforms = true }; packets.clear()
            local(MotionEvent.ACTION_DOWN, listOf(P(1, 100f, 100f)))
            local(MotionEvent.ACTION_POINTER_DOWN or (1 shl 8), listOf(P(1, 100f, 100f), P(2, 200f, 100f)))
            SystemClock.sleep(20)
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 100f, 120f), P(2, 200f, 120f)))
            local(MotionEvent.ACTION_POINTER_UP or (1 shl 8), listOf(P(1, 100f, 120f), P(2, 200f, 120f)))
            assertFalse(packets.any { it.kind == "scrollEnd" })
            local(MotionEvent.ACTION_UP, listOf(P(1, 100f, 120f)))
            assertEquals(1, packets.count { it.kind == "scrollEnd" })
            scenario.onActivity { view.get().reset() }; packets.clear()
            local(MotionEvent.ACTION_DOWN, listOf(P(1, 100f, 100f)))
            local(MotionEvent.ACTION_POINTER_DOWN or (1 shl 8), listOf(P(1, 100f, 100f), P(2, 200f, 100f)))
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 100f, 120f), P(2, 200f, 120f)))
            packets.clear()
            local(MotionEvent.ACTION_CANCEL, listOf(P(1, 100f, 120f), P(2, 200f, 120f)))
            assertEquals(listOf("reset"), packets.map { it.kind })
            scenario.onActivity { view.get().pressureClick = true }; packets.clear()
            local(MotionEvent.ACTION_DOWN, listOf(P(1, 100f, 100f)))
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 100f, 100f)))
            assertFalse(packets.any { it.kind == "down" })
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 100f, 100f, 1.7f)))
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 115f, 100f, 1.7f)))
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 115f, 100f, 1.2f)))
            // Some devices retain their last pressure on UP; that must never re-press.
            local(MotionEvent.ACTION_UP, listOf(P(1, 115f, 100f, 1.7f)))
            assertEquals(1, packets.count { it.kind == "down" })
            assertEquals(1, packets.count { it.kind == "up" })
            assertFalse(packets.any { it.kind == "click" })
            scenario.onActivity { view.get().reset() }; packets.clear()
            local(MotionEvent.ACTION_DOWN, listOf(P(1, 100f, 100f)))
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 100f, 100f, 1.7f)))
            local(MotionEvent.ACTION_CANCEL, listOf(P(1, 100f, 100f, 1.7f)))
            val cancelledCount = packets.size
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 110f, 100f, 1.7f)))
            assertEquals(cancelledCount, packets.size)
            assertEquals("reset", packets.last().kind)
            scenario.onActivity { view.get().reset(); view.get().pressureClick = false; view.get().engine.holdToClick = true; view.get().engine.tapToClick = false }; packets.clear()
            local(MotionEvent.ACTION_DOWN, listOf(P(1, 100f, 100f)))
            await("Native hold timer did not press") { packets.any { it.kind == "down" } }
            local(MotionEvent.ACTION_MOVE, listOf(P(1, 115f, 100f)))
            local(MotionEvent.ACTION_UP, listOf(P(1, 115f, 100f)))
            assertEquals(1, packets.count { it.kind == "down" })
            assertEquals(1, packets.count { it.kind == "up" })
            assertFalse(packets.any { it.kind == "click" })
        }
    }
    @Test fun appConnectsAndSendsMultiTouchToMac() {
        val args = InstrumentationRegistry.getArguments()
        val key = args.getString("pairingKey")
        assumeTrue("Requires the isolated Mac fixture", key != null)
        instrumentation.targetContext.getSharedPreferences("touchpad", 0).edit().putBoolean("threeFingerDrag", true).commit()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            onView(withId(R.id.mac_host)).perform(replaceText("10.0.2.2"))
            onView(withId(R.id.pairing_key)).perform(replaceText(key!!), closeSoftKeyboard())
            onView(withText("手动连接")).perform(click())
            val surface = AtomicReference<TouchpadView?>()
            await("Android app failed to connect to Mac") { scenario.onActivity { surface.set(it.findViewById(R.id.touchpad_surface)) }; surface.get() != null }
            capture("connected.png")
            assertTrue(instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_FREEZE_90))
            try {
            await("Landscape layout did not settle") {
                var landscape = false
                scenario.onActivity { surface.get()?.let { view -> landscape = view.width > view.height } }
                landscape
            }
            instrumentation.uiAutomation.waitForIdle(500, 5000)
            SystemClock.sleep(1000) // Allow the compositor rotation animation to finish before capture.
            capture("landscape.png")
            val position = IntArray(2)
            var cx = 0f; var cy = 0f; var density = 1f
            scenario.onActivity { surface.get()!!.apply { getLocationOnScreen(position); cx = position[0] + width / 2f; cy = position[1] + height / 2f; density = resources.displayMetrics.density } }
            val down = SystemClock.uptimeMillis()
            fun send(action: Int, points: List<P>) {
                val e = event(action, points.map { P(it.id, cx + it.x * density, cy + it.y * density) }, down)
                try { assertTrue(instrumentation.uiAutomation.injectInputEvent(e, true)) } finally { e.recycle() }
                SystemClock.sleep(25)
            }
            send(MotionEvent.ACTION_DOWN, listOf(P(1, -50f, 0f)))
            send(MotionEvent.ACTION_POINTER_DOWN or (1 shl 8), listOf(P(1, -50f, 0f), P(2, 50f, 0f)))
            send(MotionEvent.ACTION_MOVE, listOf(P(1, -56.25f, 0f), P(2, 56.25f, 0f)))
            send(MotionEvent.ACTION_POINTER_UP or (1 shl 8), listOf(P(1, -56.25f, 0f), P(2, 56.25f, 0f)))
            send(MotionEvent.ACTION_UP, listOf(P(1, -56.25f, 0f)))
            send(MotionEvent.ACTION_DOWN, listOf(P(1, -50f, 0f)))
            send(MotionEvent.ACTION_POINTER_DOWN or (1 shl 8), listOf(P(1, -50f, 0f), P(2, 50f, 0f)))
            send(MotionEvent.ACTION_MOVE, listOf(P(1, -49.00333f, -9.933467f), P(2, 49.00333f, 9.933467f)))
            send(MotionEvent.ACTION_POINTER_UP or (1 shl 8), listOf(P(1, -49.00333f, -9.933467f), P(2, 49.00333f, 9.933467f)))
            send(MotionEvent.ACTION_UP, listOf(P(1, -49.00333f, -9.933467f)))
            send(MotionEvent.ACTION_DOWN, listOf(P(1, -50f, 0f)))
            send(MotionEvent.ACTION_POINTER_DOWN or (1 shl 8), listOf(P(1, -50f, 0f), P(2, 50f, 0f)))
            send(MotionEvent.ACTION_MOVE, listOf(P(1, -50f, 15f), P(2, 50f, 15f)))
            send(MotionEvent.ACTION_POINTER_UP or (1 shl 8), listOf(P(1, -50f, 15f), P(2, 50f, 15f)))
            send(MotionEvent.ACTION_UP, listOf(P(1, -50f, 15f)))
            send(MotionEvent.ACTION_DOWN, listOf(P(1, -50f, 0f)))
            send(MotionEvent.ACTION_POINTER_DOWN or (1 shl 8), listOf(P(1, -50f, 0f), P(2, 0f, 0f)))
            send(MotionEvent.ACTION_POINTER_DOWN or (2 shl 8), listOf(P(1, -50f, 0f), P(2, 0f, 0f), P(3, 50f, 0f)))
            send(MotionEvent.ACTION_MOVE, listOf(P(1, -38f, 0f), P(2, 12f, 0f), P(3, 62f, 0f)))
            // Stop while dragging; the application must release the remote button itself.
            scenario.moveToState(Lifecycle.State.CREATED)
            SystemClock.sleep(150)
            } finally { instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE) }
        }
    }
}
