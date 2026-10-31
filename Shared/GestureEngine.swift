import Foundation

struct TouchPoint: Equatable {
    var id: Int
    var x: Double
    var y: Double
}

/// Operates on complete touch snapshots, independent of UIKit delivery order.
struct GestureEngine {
    enum ThreeFingerMode { case swipe, drag }
    var threeFingerMode: ThreeFingerMode = .swipe
    var tapToClick = true
    var tapToDrag = false
    var nativeTransforms = false
    var emit: (InputPacket.Kind, Double, Double, Int) -> Void = { _, _, _, _ in }
    private var previous: [TouchPoint] = []
    private var origin: [TouchPoint] = []
    private var began = 0.0
    private var maximum = 0
    private var moved = false
    private var swiped = false
    private var scrolling = false
    private var dragging = false
    private enum PairMode { case undecided, scroll, transform }
    private var pairMode: PairMode = .undecided
    private var zooming = false
    private var rotating = false
    private var totalRotation = 0.0
    private mutating func endTransforms() {
        if zooming { emit(.zoomEnd, 0, 0, 2) }
        if rotating { emit(.rotateEnd, 0, 0, 2) }
        zooming = false; rotating = false; totalRotation = 0; pairMode = .undecided
    }
    private func vector(_ points: [TouchPoint]) -> (length: Double, angle: Double) {
        let ordered = points.sorted { $0.id < $1.id }
        let dx = ordered[1].x - ordered[0].x, dy = ordered[1].y - ordered[0].y
        return (max(hypot(dx, dy), 1), atan2(dy, dx))
    }
    private mutating func updatePair(_ points: [TouchPoint], dx: Double, dy: Double) {
        let current = vector(points), initial = vector(origin), old = vector(previous)
        var angle = current.angle - old.angle
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }
        totalRotation += angle
        let logScale = log(current.length / initial.length)
        let cx = (points[0].x + points[1].x - origin[0].x - origin[1].x) / 2
        let cy = (points[0].y + points[1].y - origin[0].y - origin[1].y) / 2
        let translation = hypot(cx, cy)
        let shapeMotion = max(abs(logScale), abs(totalRotation)) * initial.length / 2
        if shapeMotion > 3 { moved = true }
        let transform = nativeTransforms && shapeMotion > 3 && initial.length >= 12 && (abs(logScale) > 0.035 || abs(totalRotation) > 0.07) && shapeMotion > translation * 0.8
        if transform && (pairMode == .undecided || (pairMode == .scroll && (abs(logScale) > 0.12 || abs(totalRotation) > 0.15))) {
            if scrolling { emit(.scrollEnd, 0, 0, 2); emit(.contact, 0, 0, 2); scrolling = false }
            pairMode = .transform
        }
        if pairMode == .undecided && translation > 6 && translation >= shapeMotion * 1.2 { pairMode = .scroll }
        if pairMode != .undecided {
            moved = true
            if pendingTwoTap != nil { flushTwoTap() }
        }
        if pairMode == .scroll {
            if !scrolling { emit(.scrollBegin, 0, 0, 2); scrolling = true; emit(.scroll, cx, cy, 2) }
            else if dx != 0 || dy != 0 { emit(.scroll, dx, dy, 2) }
        } else if pairMode == .transform {
            if !zooming && abs(logScale) > 0.035 {
                zooming = true; emit(.zoomBegin, 0, 0, 2); emit(.zoom, current.length / initial.length - 1, 0, 2)
            } else if zooming && current.length != old.length { emit(.zoom, current.length / old.length - 1, 0, 2) }
            if !rotating && abs(totalRotation) > 0.07 {
                rotating = true; emit(.rotateBegin, 0, 0, 2); emit(.rotate, -totalRotation * 180 / .pi, 0, 2)
            } else if rotating && angle != 0 { emit(.rotate, -angle * 180 / .pi, 0, 2) }
        }
    }
    private var tapDragCandidate = false
    private var tapDragging = false
    private var lastTap: (time: Double, point: TouchPoint)?
    private var pendingTwoTap: (time: Double, point: TouchPoint)?
    private var smartZoomCandidate = false
    private var lastTwoPoint = TouchPoint(id: 0, x: 0, y: 0)
    var needsClock: Bool { tapDragCandidate || pendingTwoTap != nil }
    private mutating func flushTwoTap() {
        if pendingTwoTap != nil { emit(.click, 0, 0, 2); pendingTwoTap = nil }
        smartZoomCandidate = false
    }

    mutating func advance(at time: Double) {
        if let pendingTwoTap, time - pendingTwoTap.time >= 0.28 && (!smartZoomCandidate || time - began >= 0.3) { flushTwoTap() }
        if tapDragCandidate && previous.count == 1 && time - began >= 0.2 {
            beginTapDrag()
        }
    }
    private mutating func beginTapDrag() {
        tapDragCandidate = false; tapDragging = true; moved = true
        emit(.down, 0, 0, 1)
    }

    mutating func update(_ snapshot: [TouchPoint], at time: Double) {
        if let pendingTwoTap, time - pendingTwoTap.time >= 0.28 && !smartZoomCandidate { flushTwoTap() }
        let points = snapshot.sorted { $0.id < $1.id }
        guard !points.isEmpty || !previous.isEmpty else { return }
        if previous.isEmpty && !points.isEmpty {
            began = time; maximum = 0; moved = false; swiped = false
            if tapToClick && tapToDrag && points.count == 1, let lastTap {
                tapDragCandidate = time - lastTap.time <= 0.35 && time >= lastTap.time && hypot(points[0].x - lastTap.point.x, points[0].y - lastTap.point.y) <= 40
            } else { tapDragCandidate = false }
            lastTap = nil
            emit(.contact, 0, 0, points.count)
        }
        maximum = max(maximum, points.count)
        let oldIDs = Set(previous.map(\.id)), newIDs = Set(points.map(\.id))
        let idsChanged = oldIDs != newIDs
        let addedFinger = !newIDs.subtracting(oldIDs).isEmpty
        if idsChanged { endTransforms() }
        // Wait for the last finger on staggered lift-off; a long remaining hold suppresses momentum by age.
        if scrolling && (points.isEmpty || points.count > 2 || addedFinger || (points.count == 2 && idsChanged)) {
            emit(.scrollEnd, 0, 0, 2); scrolling = false
        }
        if dragging && (points.count != 3 || idsChanged) {
            emit(.up, 0, 0, 3); dragging = false
        }
        if tapDragging && (points.count != 1 || idsChanged) {
            emit(.up, 0, 0, 1); tapDragging = false; moved = true
        }
        if points.count > 1 { tapDragCandidate = false }
        if points.isEmpty {
            if tapToClick && maximum <= 2 && !moved && time - began < 0.3 {
                if maximum == 2 && nativeTransforms {
                    if smartZoomCandidate && pendingTwoTap != nil {
                        pendingTwoTap = nil; smartZoomCandidate = false; emit(.smartZoom, 0, 0, 2)
                    } else {
                        flushTwoTap(); pendingTwoTap = (time, lastTwoPoint)
                    }
                } else {
                    flushTwoTap()
                    emit(.click, 0, 0, maximum)
                    if maximum == 1, let point = previous.first { lastTap = (time, point) }
                }
            }
            tapDragCandidate = false
            previous = []; origin = []; return
        }
        if points.count == 2 {
            lastTwoPoint = TouchPoint(id: 0, x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2)
        }
        if idsChanged {
            if points.count == 2 && maximum == 2, let pendingTwoTap {
                smartZoomCandidate = time - pendingTwoTap.time <= 0.28 && hypot(lastTwoPoint.x - pendingTwoTap.point.x, lastTwoPoint.y - pendingTwoTap.point.y) <= 40
            }
            if !previous.isEmpty && addedFinger { emit(.contact, 0, 0, points.count) }
            origin = points; previous = points
            // Once a second finger has joined, lifting it cannot turn the rest into a pointer gesture.
            return
        }
        let dx = points.reduce(0.0) { sum, p in sum + p.x - (previous.first { $0.id == p.id }?.x ?? p.x) } / Double(points.count)
        let dy = points.reduce(0.0) { sum, p in sum + p.y - (previous.first { $0.id == p.id }?.y ?? p.y) } / Double(points.count)
        let travel = points.map { p in
            let start = origin.first { $0.id == p.id } ?? p
            return hypot(p.x - start.x, p.y - start.y)
        }.max() ?? 0
        if travel > 8 { moved = true }
        if maximum == 1 && points.count == 1 {
            if tapDragCandidate {
                if travel > 4 {
                    beginTapDrag()
                    emit(.move, points[0].x - origin[0].x, points[0].y - origin[0].y, 1)
                }
            } else if dx != 0 || dy != 0 { emit(.move, dx, dy, 1) }
        } else if maximum == 2 && points.count == 2 {
            updatePair(points, dx: dx, dy: dy)
        } else if maximum == 3 && points.count == 3 && threeFingerMode == .drag && (travel > 8 || dragging) {
            if !dragging {
                emit(.down, 0, 0, 3); dragging = true
                let x = zip(points, origin).reduce(0.0) { $0 + $1.0.x - $1.1.x } / Double(points.count)
                let y = zip(points, origin).reduce(0.0) { $0 + $1.0.y - $1.1.y } / Double(points.count)
                if x != 0 || y != 0 { emit(.move, x, y, 3) }
            } else if dx != 0 || dy != 0 { emit(.move, dx, dy, 3) }
        } else if points.count >= 3 && !swiped && travel > 60 {
            let ox = origin.reduce(0) { $0 + $1.x } / Double(origin.count)
            let oy = origin.reduce(0) { $0 + $1.y } / Double(origin.count)
            let x = points.reduce(0) { $0 + $1.x } / Double(points.count) - ox
            let y = points.reduce(0) { $0 + $1.y } / Double(points.count) - oy
            // A single moving finger or opposing fingers must not switch spaces.
            let averageTravel = points.reduce(0.0) { sum, p in
                let start = origin.first { $0.id == p.id } ?? p
                return sum + hypot(p.x - start.x, p.y - start.y)
            } / Double(points.count)
            if hypot(x, y) > 60 && hypot(x, y) >= averageTravel * 0.75 {
                emit(.swipe, x, y, points.count); swiped = true
            }
        }
        previous = points
    }
    mutating func cancel() {
        emit(.reset, 0, 0, 1)
        previous = []; origin = []; maximum = 0
        scrolling = false; dragging = false; moved = false; swiped = false
        zooming = false; rotating = false; totalRotation = 0; pairMode = .undecided
        tapDragCandidate = false; tapDragging = false; lastTap = nil
        pendingTwoTap = nil; smartZoomCandidate = false
    }
}
