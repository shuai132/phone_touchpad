import AppKit
@main struct NativeGestureEncodingCheck {
    static func main() {
        precondition(NativeGestures.supported, "This OS does not support the experimental gesture encoding")
        let phases: [(NativeGestures.Phase, NSEvent.Phase)] = [(.began, .began), (.changed, .changed), (.ended, .ended), (.cancelled, .cancelled)]
        for (phase, expected) in phases {
            let zoom = NSEvent(cgEvent: NativeGestures.event(kind: .zoom, value: 0.25, phase: phase)!)!
            precondition(zoom.type == .magnify && zoom.phase == expected && zoom.magnification == 0.25)
            let rotation = NSEvent(cgEvent: NativeGestures.event(kind: .rotate, value: -15, phase: phase)!)!
            precondition(rotation.type == .rotate && rotation.phase == expected && rotation.rotation == -15)
        }
        precondition(NativeGestures.event(kind: .zoom, value: .nan, phase: .changed) == nil)
        print("AppKit native gesture values and phase encoding checks passed")
    }
}
