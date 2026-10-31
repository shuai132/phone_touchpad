import AppKit

/// Isolated interoperability adapter for undocumented CGEvent gesture fields.
/// Field definitions are documented in WebKit's CoreGraphicsTestSPI.h and IOKitSPIMac.h.
/// Runtime read-back checks fail closed if AppKit stops interpreting this encoding.
struct NativeGestures {
    enum Kind: Int64, CaseIterable { case zoom = 8, rotate = 5, smartZoom = 22 }
    enum Phase: Int64 { case none = 0, began = 1, changed = 2, ended = 4, cancelled = 8 }
    private var active: Set<Kind> = []
    private let postEvent: (CGEvent) -> Void
    init(postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) { self.postEvent = postEvent }
    private func post(_ event: CGEvent?) { if let event { postEvent(event) } }
    static let supported = checkEncoding()
    static func scaledMagnification(_ delta: Double, sensitivity: Double) -> Double {
        guard delta.isFinite else { return 0 }
        let gain = sensitivity.isFinite ? min(max(sensitivity, 0.1), 1.5) : 0.35
        // Scale logarithmic distance so the result is independent of sample frequency.
        return expm1(log1p(min(max(delta, -0.95), 3)) * gain)
    }

    static func event(kind: Kind, value: Double = 0, phase: Phase, location: CGPoint? = nil) -> CGEvent? {
        guard value.isFinite, let event = CGEvent(source: nil),
              let type = CGEventType(rawValue: 29), let subtype = CGEventField(rawValue: 110),
              let phaseField = CGEventField(rawValue: 132),
              let valueField = CGEventField(rawValue: kind == .rotate ? 114 : 113) else { return nil }
        event.type = type
        event.setIntegerValueField(subtype, value: kind.rawValue)
        event.setIntegerValueField(phaseField, value: phase.rawValue)
        event.setDoubleValueField(valueField, value: value)
        if let location { event.location = location }
        return event
    }
    private static func checkEncoding() -> Bool {
        guard let zoom = event(kind: .zoom, value: 0.125, phase: .changed).flatMap({ NSEvent(cgEvent: $0) }),
              let rotate = event(kind: .rotate, value: -12.5, phase: .changed).flatMap({ NSEvent(cgEvent: $0) }),
              let smart = event(kind: .smartZoom, phase: .none).flatMap({ NSEvent(cgEvent: $0) }) else { return false }
        return zoom.type == .magnify && zoom.phase == .changed && abs(zoom.magnification - 0.125) < 0.0001 && rotate.type == .rotate && rotate.phase == .changed && abs(Double(rotate.rotation) + 12.5) < 0.0001 && smart.type == .smartMagnify
    }
    mutating func send(_ kind: Kind, value: Double = 0, phase: Phase) {
        guard Self.supported else { return }
        if kind == .smartZoom {
            post(Self.event(kind: kind, phase: .none)); return
        }
        if phase == .began { active.insert(kind) }
        guard active.contains(kind) else { return }
        post(Self.event(kind: kind, value: value, phase: phase))
        if phase == .ended || phase == .cancelled { active.remove(kind) }
    }
    mutating func cancel() {
        for kind in active { post(Self.event(kind: kind, phase: .cancelled)) }
        active.removeAll()
    }
}
