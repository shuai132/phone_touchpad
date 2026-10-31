import SwiftUI
import UIKit

struct TouchSurface: UIViewRepresentable {
    var threeFingerDrag: Bool
    var tapToClick: Bool
    var tapToDrag: Bool
    var active: Bool
    var nativeTransforms: Bool
    var pressureToClick: Bool
    var holdToClick: Bool
    var emit: (InputPacket.Kind, Double, Double, Int, Double) -> Void
    func makeUIView(context: Context) -> PadView { PadView() }
    func updateUIView(_ view: PadView, context: Context) {
        view.setActive(active)
        view.engine.nativeTransforms = nativeTransforms
        view.engine.tapToClick = tapToClick
        view.engine.tapToDrag = tapToDrag
        view.engine.pressureToClick = pressureToClick
        view.engine.holdToClick = holdToClick
        view.engine.threeFingerMode = threeFingerDrag ? .drag : .swipe
        view.engine.emit = { [weak view] kind, x, y, fingers in
            view?.recordAction(kind)
            emit(kind, x, y, fingers, view?.sampleTime ?? ProcessInfo.processInfo.systemUptime)
            if kind == .click || kind == .down || kind == .up { view?.clickFeedback(pressed: kind == .down) }
        }
    }
    static func dismantleUIView(_ view: PadView, coordinator: ()) { view.reset() }
}
final class PadView: UIView {
    var engine = GestureEngine()
    private(set) var sampleTime = ProcessInfo.processInfo.systemUptime
    private var touches: [ObjectIdentifier: (Int, UITouch)] = [:]
    private var nextID = 0
    private var lastTouchFrame: TouchFrame?
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private let pressFeedback = UIImpactFeedbackGenerator(style: .medium)
    func clickFeedback(pressed: Bool = false) {
        let generator = pressed ? pressFeedback : feedback
        generator.impactOccurred(); generator.prepare()
    }
    private var holdTimer: Timer?
    private var active = false
    private var previousSize: CGSize?
    #if DEBUG
    private var diagnosticActions: [String: Int] = [:]
    private var diagnosticMaximum = 0
    private var diagnosticFrames = 0
    private var diagnosticStart = 0.0
    private static let diagnosticQueue = DispatchQueue(label: "touchpad.input-diagnostics")
    #endif
    func recordAction(_ kind: InputPacket.Kind) {
        #if DEBUG
        diagnosticActions[kind.rawValue, default: 0] += 1
        #endif
    }
    private func saveDiagnostics(reason: String) {
        #if DEBUG
        guard diagnosticFrames > 0 else { return }
        // Only the most recent gesture summary is kept; no coordinates, keys or host names.
        let report: [String: Any] = ["reason": reason, "maximumFingers": diagnosticMaximum,
            "frames": diagnosticFrames, "duration": max(0, sampleTime - diagnosticStart),
            "actions": diagnosticActions, "nativeTransforms": engine.nativeTransforms,
            "threeFingerDrag": engine.threeFingerMode == .drag]
        guard let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        Self.diagnosticQueue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? bytes.write(to: directory.appendingPathComponent("input-diagnostics.json"), options: .atomic)
        }
        #endif
    }
    func setActive(_ value: Bool) {
        if active && !value { reset(reason: "inactive") }
        active = value; isUserInteractionEnabled = value
    }
    func reset(reason: String = "reset") {
        holdTimer?.invalidate(); holdTimer = nil
        sampleTime = ProcessInfo.processInfo.systemUptime
        touches.removeAll(); lastTouchFrame = nil; engine.cancel(); saveDiagnostics(reason: reason)
    }
    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sampleTime = ProcessInfo.processInfo.systemUptime
            self.engine.advance(at: self.sampleTime)
            if self.touches.isEmpty && !self.engine.needsClock { self.holdTimer?.invalidate(); self.holdTimer = nil }
        }
        holdTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = true }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let previousSize, previousSize != bounds.size {
            // Touch locations from different layouts must not form one gesture.
            reset(reason: "layoutChanged")
        }
        previousSize = bounds.size
    }
    private func points() -> [TouchPoint] {
        touches.values.map { id, touch in
            let p = touch.location(in: self)
            return TouchPoint(id: id, x: p.x, y: p.y, pressure: pressure(of: touch))
        }
    }
    private func pressure(of touch: UITouch) -> Double? {
        guard engine.pressureToClick, traitCollection.forceTouchCapability == .available,
              touch.type == .direct, touch.maximumPossibleForce > 0 else { return nil }
        if touch.phase == .ended || touch.phase == .cancelled { return 0 }
        let value = Double(touch.force / touch.maximumPossibleForce)
        return value.isFinite ? min(max(value, 0), 1) : nil
    }
    private func consume(_ frame: TouchFrame) {
        #if DEBUG
        diagnosticFrames += 1; diagnosticMaximum = max(diagnosticMaximum, frame.points.count)
        #endif
        sampleTime = frame.time; engine.update(frame.points, at: frame.time); lastTouchFrame = frame
    }
    private func snapshot(at time: Double) {
        consume(TouchFrame(time: max(time, lastTouchFrame?.time ?? time), points: points()))
    }
    private func replayMotion(event: UIEvent?) {
        let trajectories = touches.values.map { id, touch in
            TouchTrajectory(id: id, samples: (event?.coalescedTouches(for: touch) ?? []).map { sample in
                let p = sample.location(in: self)
                return TouchSample(time: sample.timestamp, x: p.x, y: p.y, pressure: pressure(of: sample))
            })
        }
        let eventTime = event?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let recordedTime = trajectories.flatMap(\.samples).map(\.time).filter(\.isFinite).max() ?? eventTime
        let latest = TouchFrame(time: max(eventTime, recordedTime, lastTouchFrame?.time ?? eventTime), points: points())
        for frame in TouchFrameSampler.frames(from: lastTouchFrame, to: latest, trajectories: trajectories) { consume(frame) }
    }
    override func touchesBegan(_ new: Set<UITouch>, with event: UIEvent?) {
        #if DEBUG
        if touches.isEmpty {
            diagnosticActions = [:]; diagnosticMaximum = 0; diagnosticFrames = 0
            diagnosticStart = event?.timestamp ?? ProcessInfo.processInfo.systemUptime
        }
        #endif
        feedback.prepare(); pressFeedback.prepare()
        for touch in new { nextID += 1; touches[ObjectIdentifier(touch)] = (nextID, touch) }
        snapshot(at: event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        startHoldTimer()
    }
    override func touchesMoved(_ changed: Set<UITouch>, with event: UIEvent?) {
        replayMotion(event: event)
    }
    override func touchesEnded(_ ended: Set<UITouch>, with event: UIEvent?) {
        // Replay the final recorded movement before deciding whether this was a tap.
        replayMotion(event: event)
        for touch in ended { touches.removeValue(forKey: ObjectIdentifier(touch)) }
        snapshot(at: event?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        if touches.isEmpty { saveDiagnostics(reason: "ended") }
        if touches.isEmpty && !engine.needsClock { holdTimer?.invalidate(); holdTimer = nil }
    }
    override func touchesCancelled(_ cancelled: Set<UITouch>, with event: UIEvent?) {
        reset(reason: "systemCancelled")
    }
}
