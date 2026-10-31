package dev.phonetouchpad.core

import kotlin.math.*

data class TouchPoint(val id: Int, val x: Double, val y: Double)

/** Native touch snapshots use the same gesture rules and wire phases as the iOS engine. */
class GestureEngine(var emit: (Packet) -> Unit = {}) {
    enum class ThreeFingerMode { SWIPE, DRAG }
    private enum class PairMode { UNDECIDED, SCROLL, TRANSFORM }
    var threeFingerMode = ThreeFingerMode.SWIPE
    var tapToClick = true
    var tapToDrag = false
    var nativeTransforms = false
    private var previous = emptyList<TouchPoint>()
    private var origin = emptyList<TouchPoint>()
    private var began = 0.0
    private var maximum = 0
    private var moved = false
    private var swiped = false
    private var scrolling = false
    private var dragging = false
    private var pairMode = PairMode.UNDECIDED
    private var zooming = false
    private var rotating = false
    private var totalRotation = 0.0
    private var tapDragCandidate = false
    private var tapDragging = false
    private data class Tap(val time: Double, val point: TouchPoint)
    private var lastTap: Tap? = null
    private var pendingTwoTap: Tap? = null
    private var smartZoomCandidate = false
    private var lastTwoPoint = TouchPoint(0, 0.0, 0.0)
    private var clock = 0.0
    val needsClock get() = tapDragCandidate || pendingTwoTap != null
    private fun output(kind: String, x: Double = 0.0, y: Double = 0.0, fingers: Int = 1) = emit(Packet(kind, x, y, fingers, clock))
    private fun flushTwoTap() {
        if (pendingTwoTap != null) { output("click", fingers = 2); pendingTwoTap = null }
        smartZoomCandidate = false
    }
    fun advance(time: Double) {
        clock = time
        pendingTwoTap?.let { if (time - it.time >= 0.28 && (!smartZoomCandidate || time - began >= 0.3)) flushTwoTap() }
        if (tapDragCandidate && previous.size == 1 && time - began >= 0.2) beginTapDrag()
    }
    private fun beginTapDrag() {
        tapDragCandidate = false; tapDragging = true; moved = true; output("down")
    }
    private fun endTransforms() {
        if (zooming) output("zoomEnd", fingers = 2)
        if (rotating) output("rotateEnd", fingers = 2)
        zooming = false; rotating = false; totalRotation = 0.0; pairMode = PairMode.UNDECIDED
    }
    private fun vector(points: List<TouchPoint>): Pair<Double, Double> {
        val ordered = points.sortedBy { it.id }
        val dx = ordered[1].x - ordered[0].x; val dy = ordered[1].y - ordered[0].y
        return max(hypot(dx, dy), 1.0) to atan2(dy, dx)
    }
    private fun updatePair(points: List<TouchPoint>, dx: Double, dy: Double) {
        val (length, angle) = vector(points); val (initial, _) = vector(origin); val (oldLength, oldAngle) = vector(previous)
        var delta = angle - oldAngle
        if (delta > PI) delta -= 2 * PI
        if (delta < -PI) delta += 2 * PI
        totalRotation += delta
        val logScale = ln(length / initial)
        val cx = (points.sumOf { it.x } - origin.sumOf { it.x }) / 2
        val cy = (points.sumOf { it.y } - origin.sumOf { it.y }) / 2
        val translation = hypot(cx, cy)
        val shapeMotion = max(abs(logScale), abs(totalRotation)) * initial / 2
        if (shapeMotion > 3) moved = true
        val transform = nativeTransforms && shapeMotion > 3 && initial >= 12 && (abs(logScale) > 0.035 || abs(totalRotation) > 0.07) && shapeMotion > translation * 0.8
        if (transform && (pairMode == PairMode.UNDECIDED || (pairMode == PairMode.SCROLL && (abs(logScale) > 0.12 || abs(totalRotation) > 0.15)))) {
            if (scrolling) { output("scrollEnd", fingers = 2); output("contact", fingers = 2); scrolling = false }
            pairMode = PairMode.TRANSFORM
        }
        if (pairMode == PairMode.UNDECIDED && translation > 6 && translation >= shapeMotion * 1.2) pairMode = PairMode.SCROLL
        if (pairMode != PairMode.UNDECIDED) { moved = true; if (pendingTwoTap != null) flushTwoTap() }
        if (pairMode == PairMode.SCROLL) {
            if (!scrolling) { output("scrollBegin", fingers = 2); scrolling = true; output("scroll", cx, cy, 2) }
            else if (dx != 0.0 || dy != 0.0) output("scroll", dx, dy, 2)
        } else if (pairMode == PairMode.TRANSFORM) {
            if (!zooming && abs(logScale) > 0.035) { zooming = true; output("zoomBegin", fingers = 2); output("zoom", length / initial - 1, fingers = 2) }
            else if (zooming && length != oldLength) output("zoom", length / oldLength - 1, fingers = 2)
            if (!rotating && abs(totalRotation) > 0.07) { rotating = true; output("rotateBegin", fingers = 2); output("rotate", -totalRotation * 180 / PI, fingers = 2) }
            else if (rotating && delta != 0.0) output("rotate", -delta * 180 / PI, fingers = 2)
        }
    }
    fun update(snapshot: List<TouchPoint>, time: Double) {
        require(time.isFinite() && snapshot.all { it.x.isFinite() && it.y.isFinite() })
        clock = time
        pendingTwoTap?.let { if (time - it.time >= 0.28 && !smartZoomCandidate) flushTwoTap() }
        val points = snapshot.sortedBy { it.id }
        if (points.isEmpty() && previous.isEmpty()) return
        if (previous.isEmpty() && points.isNotEmpty()) {
            began = time; maximum = 0; moved = false; swiped = false
            tapDragCandidate = tapToClick && tapToDrag && points.size == 1 && lastTap?.let {
                time >= it.time && time - it.time <= 0.35 && hypot(points[0].x - it.point.x, points[0].y - it.point.y) <= 40
            } == true
            lastTap = null; output("contact", fingers = points.size)
        }
        maximum = max(maximum, points.size)
        val oldIds = previous.map { it.id }.toSet(); val newIds = points.map { it.id }.toSet()
        val changed = oldIds != newIds; val added = (newIds - oldIds).isNotEmpty()
        if (changed) endTransforms()
        if (scrolling && (points.isEmpty() || points.size > 2 || added || (points.size == 2 && changed))) { output("scrollEnd", fingers = 2); scrolling = false }
        if (dragging && (points.size != 3 || changed)) { output("up", fingers = 3); dragging = false }
        if (tapDragging && (points.size != 1 || changed)) { output("up"); tapDragging = false; moved = true }
        if (points.size > 1) tapDragCandidate = false
        if (points.isEmpty()) {
            if (tapToClick && maximum <= 2 && !moved && time - began < 0.3) {
                if (maximum == 2 && nativeTransforms) {
                    if (smartZoomCandidate && pendingTwoTap != null) { pendingTwoTap = null; smartZoomCandidate = false; output("smartZoom", fingers = 2) }
                    else { flushTwoTap(); pendingTwoTap = Tap(time, lastTwoPoint) }
                } else { flushTwoTap(); output("click", fingers = maximum); if (maximum == 1) lastTap = Tap(time, previous.first()) }
            }
            tapDragCandidate = false; previous = emptyList(); origin = emptyList(); return
        }
        if (points.size == 2) lastTwoPoint = TouchPoint(0, points.sumOf { it.x } / 2, points.sumOf { it.y } / 2)
        if (changed) {
            pendingTwoTap?.let { if (points.size == 2 && maximum == 2) smartZoomCandidate = time - it.time <= 0.28 && hypot(lastTwoPoint.x - it.point.x, lastTwoPoint.y - it.point.y) <= 40 }
            if (previous.isNotEmpty() && added) output("contact", fingers = points.size)
            origin = points; previous = points; return
        }
        val dx = points.sumOf { p -> p.x - previous.first { it.id == p.id }.x } / points.size
        val dy = points.sumOf { p -> p.y - previous.first { it.id == p.id }.y } / points.size
        val travel = points.maxOf { p -> val start = origin.first { it.id == p.id }; hypot(p.x - start.x, p.y - start.y) }
        if (travel > 8) moved = true
        if (maximum == 1 && points.size == 1) {
            if (tapDragCandidate) { if (travel > 4) { beginTapDrag(); output("move", points[0].x - origin[0].x, points[0].y - origin[0].y) } }
            else if (dx != 0.0 || dy != 0.0) output("move", dx, dy)
        } else if (maximum == 2 && points.size == 2) updatePair(points, dx, dy)
        else if (maximum == 3 && points.size == 3 && threeFingerMode == ThreeFingerMode.DRAG && (travel > 8 || dragging)) {
            if (!dragging) { output("down", fingers = 3); dragging = true; output("move", (points.sumOf { it.x } - origin.sumOf { it.x }) / points.size, (points.sumOf { it.y } - origin.sumOf { it.y }) / points.size, 3) }
            else if (dx != 0.0 || dy != 0.0) output("move", dx, dy, 3)
        } else if (points.size >= 3 && !swiped && travel > 60) {
            val x = (points.sumOf { it.x } - origin.sumOf { it.x }) / points.size
            val y = (points.sumOf { it.y } - origin.sumOf { it.y }) / points.size
            val averageTravel = points.sumOf { p -> val start = origin.first { it.id == p.id }; hypot(p.x - start.x, p.y - start.y) } / points.size
            if (hypot(x, y) > 60 && hypot(x, y) >= averageTravel * 0.75) { output("swipe", x, y, points.size); swiped = true }
        }
        previous = points
    }
    fun cancel(time: Double = clock) {
        clock = time; output("reset"); previous = emptyList(); origin = emptyList(); maximum = 0
        scrolling = false; dragging = false; moved = false; swiped = false
        zooming = false; rotating = false; totalRotation = 0.0; pairMode = PairMode.UNDECIDED
        tapDragCandidate = false; tapDragging = false; lastTap = null; pendingTwoTap = null; smartZoomCandidate = false
    }
}
