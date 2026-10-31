package dev.phonetouchpad.android

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import dev.phonetouchpad.core.GestureEngine
import dev.phonetouchpad.core.Packet
import dev.phonetouchpad.core.TouchPoint
import dev.phonetouchpad.core.PressureEstimate

class TouchpadView(context: Context, private val output: (Packet) -> Unit) : View(context) {
    private val density = resources.displayMetrics.density
    private val handler = Handler(Looper.getMainLooper())
    private var down = false
    private var acceptingTouches = false
    var pressureClick = false
    private val pressureEstimate = PressureEstimate()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var positions = emptyList<TouchPoint>()
    val engine = GestureEngine { packet ->
        output(packet)
        when (packet.kind) {
            "down" -> performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            "click" -> performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
            "up" -> performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        }
    }
    private val tick = object : Runnable {
        override fun run() {
            engine.advance(SystemClock.uptimeMillis() / 1000.0)
            if (down || engine.needsClock) handler.postDelayed(this, 16)
        }
    }
    init { contentDescription = "多指触控板"; isClickable = true }
    fun reset() {
        handler.removeCallbacks(tick); engine.cancel(SystemClock.uptimeMillis() / 1000.0)
        down = false; acceptingTouches = false; pressureEstimate.reset(); positions = emptyList(); invalidate()
    }
    override fun onDetachedFromWindow() { reset(); super.onDetachedFromWindow() }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false
        parent?.requestDisallowInterceptTouchEvent(true)
        if (event.actionMasked == MotionEvent.ACTION_CANCEL) { reset(); return true }
        if (event.actionMasked == MotionEvent.ACTION_DOWN) { acceptingTouches = true; pressureEstimate.reset() }
        if (!acceptingTouches) return true
        fun pressure(index: Int, history: Int?): Double? {
            if (!pressureClick || event.pointerCount != 1 || event.getToolType(index) != MotionEvent.TOOL_TYPE_FINGER) return null
            if (history == null && event.actionMasked == MotionEvent.ACTION_UP) return 0.0
            val raw = history?.let { event.getHistoricalPressure(index, it) } ?: event.getPressure(index)
            val deep = history == null && Build.VERSION.SDK_INT >= 29 && event.classification == MotionEvent.CLASSIFICATION_DEEP_PRESS
            return pressureEstimate.sample(raw.toDouble(), deep)
        }
        fun snapshot(history: Int? = null, exclude: Int? = null): List<TouchPoint> = (0 until event.pointerCount).filter { it != exclude }.map { index ->
            TouchPoint(event.getPointerId(index), (history?.let { event.getHistoricalX(index, it) } ?: event.getX(index)) / density.toDouble(),
                (history?.let { event.getHistoricalY(index, it) } ?: event.getY(index)) / density.toDouble(), pressure(index, history))
        }
        fun time(history: Int? = null): Double = if (Build.VERSION.SDK_INT >= 34) {
            (history?.let { event.getHistoricalEventTimeNanos(it) } ?: event.eventTimeNanos) / 1e9
        } else (history?.let { event.getHistoricalEventTime(it) } ?: event.eventTime) / 1000.0
        if (event.actionMasked == MotionEvent.ACTION_MOVE || event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_POINTER_UP) {
            for (i in 0 until event.historySize) engine.update(snapshot(i), time(i))
        }
        positions = snapshot()
        engine.update(positions, time())
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_POINTER_UP) {
            positions = snapshot(exclude = event.actionIndex)
            engine.update(positions, time())
        }
        down = positions.isNotEmpty()
        if (event.actionMasked == MotionEvent.ACTION_UP) acceptingTouches = false
        handler.removeCallbacks(tick)
        if (down || engine.needsClock) handler.postDelayed(tick, 16)
        invalidate(); return true
    }
    override fun performClick(): Boolean {
        super.performClick()
        if (isEnabled) output(Packet("click", time = SystemClock.uptimeMillis() / 1000.0))
        return true
    }
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) { if (oldw != 0 && (w != oldw || h != oldh)) reset() }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.color = Color.rgb(239, 241, 245)
        canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), 24 * density, 24 * density, paint)
        paint.color = Color.argb(40, 70, 100, 180)
        for (point in positions) canvas.drawCircle((point.x * density).toFloat(), (point.y * density).toFloat(), 13 * density, paint)
        paint.color = Color.DKGRAY; paint.textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 12f, resources.displayMetrics); paint.textAlign = Paint.Align.CENTER
        canvas.drawText(if (engine.threeFingerMode == GestureEngine.ThreeFingerMode.DRAG) "单指移动 · 双指滚动 · 三指拖移" else "单指移动 · 双指滚动 · 三指切换空间", width / 2f, height - 20 * density, paint)
    }
}
