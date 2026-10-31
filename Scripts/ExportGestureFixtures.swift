import Foundation

private struct Options: Codable { var native = true; var tapDrag = false; var threeDrag = false; var tapClick = true; var hold = false; var pressure = true }
private struct Step: Codable { var action = "update"; var time: Double; var points: [Point] = [] }
private struct Point: Codable { var id: Int; var x: Double; var y: Double = 0; var pressure: Double? = nil }
private struct Trace: Codable { var name: String; var options: Options; var steps: [Step]; var expected: [InputPacket] = [] }
@main struct ExportGestureFixtures {
    static func main() throws {
        func pair(_ t: Double, _ distance: Double = 100, _ y: Double = 0) -> Step { Step(time: t, points: [Point(id: 1, x: -distance / 2, y: y), Point(id: 2, x: distance / 2, y: y)]) }
        var traces: [Trace] = [
            Trace(name: "singleTap", options: Options(), steps: [Step(time: 0, points: [Point(id: 1, x: 0)]), Step(time: 0.1)]),
            Trace(name: "staggeredScroll", options: Options(), steps: [pair(0), pair(0.02, 100, 12), pair(0.04, 100, 24), Step(time: 0.05, points: [Point(id: 1, x: -50, y: 24)]), Step(time: 0.06)]),
            Trace(name: "pinch", options: Options(), steps: [pair(0), pair(0.02, 110), pair(0.04, 121), Step(time: 0.06)]),
            Trace(name: "smartZoom", options: Options(), steps: [pair(0), Step(time: 0.05), pair(0.15), Step(time: 0.2), Step(action: "advance", time: 0.6)]),
            Trace(name: "rightClickDelay", options: Options(), steps: [pair(0), Step(time: 0.05), Step(action: "advance", time: 0.4)]),
            Trace(name: "tapDragHold", options: Options(tapDrag: true), steps: [Step(time: 0, points: [Point(id: 1, x: 0)]), Step(time: 0.05), Step(time: 0.1, points: [Point(id: 1, x: 0)]), Step(action: "advance", time: 0.31), Step(time: 0.35, points: [Point(id: 1, x: 10)]), Step(time: 0.4)]),
            Trace(name: "cancelScroll", options: Options(), steps: [pair(0), pair(0.02, 100, 20), Step(action: "cancel", time: 0.03)])
        ]
        func press(_ time: Double, _ pressure: Double, x: Double = 0) -> Step { Step(time: time, points: [Point(id: 1, x: x, pressure: pressure)]) }
        traces += [
            Trace(name: "pressureHysteresisDrag", options: Options(), steps: [press(0, 0.1), press(0.1, 0.6), press(0.12, 0.5), press(0.2, 0.7, x: 12), press(0.3, 0.3, x: 12), Step(time: 0.4)]),
            Trace(name: "pressureRepress", options: Options(), steps: [press(0, 0.6), press(0.1, 0.3), press(0.2, 0.7), Step(time: 0.25)]),
            Trace(name: "pressureReleaseMotion", options: Options(), steps: [press(0, 0.7), press(0.1, 0.2, x: 15), Step(time: 0.2)]),
            Trace(name: "holdWithoutTimerTick", options: Options(hold: true), steps: [Step(time: 0, points: [Point(id: 1, x: 0)]), Step(time: 0.36)]),
            Trace(name: "pressureCancel", options: Options(), steps: [press(0, 0.7), Step(action: "cancel", time: 0.1)]),
            Trace(name: "holdPressDrag", options: Options(tapClick: false, hold: true), steps: [Step(time: 0, points: [Point(id: 1, x: 0)]), Step(action: "advance", time: 0.36), Step(time: 0.4, points: [Point(id: 1, x: 15)]), Step(time: 0.5)]),
            Trace(name: "movingCannotHoldPress", options: Options(hold: true), steps: [Step(time: 0, points: [Point(id: 1, x: 0)]), Step(time: 0.1, points: [Point(id: 1, x: 20)]), Step(action: "advance", time: 0.8), Step(time: 0.9)]),
            Trace(name: "pressureFingerAdded", options: Options(), steps: [press(0, 0.7), Step(time: 0.1, points: [Point(id: 1, x: 0, pressure: 0.7), Point(id: 2, x: 50)]), Step(time: 0.2)])
        ]
        let three = [Point(id: 1, x: 0), Point(id: 2, x: 50), Point(id: 3, x: 100)]
        var dragSteps = [Step(time: 0, points: three)]
        for index in 1...6 {
            let offset = Double(index * 2)
            let movedPoints = three.map { Point(id: $0.id, x: $0.x + offset) }
            dragSteps.append(Step(time: Double(index) / 100, points: movedPoints))
        }
        dragSteps.append(Step(time: 0.1))
        traces.append(Trace(name: "slowThreeDrag", options: Options(threeDrag: true), steps: dragSteps))
        traces.append(Trace(name: "threeSwipe", options: Options(), steps: [Step(time: 0, points: three), Step(time: 0.1, points: three.map { Point(id: $0.id, x: $0.x + 80) }), Step(time: 0.2)]))
        // Deterministic continuous two-finger transforms cover numerical equivalence between native engines.
        for index in 0..<20 {
            let steps = (0..<24).map { frame -> Step in
                let angle = 3.051 + Double(frame) * Double(index + 1) / 307
                let length = 100 + sin(Double(frame) / 5) * Double(index + 1)
                let center = Double(frame * (index % 3))
                return Step(time: Double(frame) / 120, points: [Point(id: 1, x: center - cos(angle) * length / 2, y: -sin(angle) * length / 2), Point(id: 2, x: center + cos(angle) * length / 2, y: sin(angle) * length / 2)])
            }
            traces.append(Trace(name: "continuous-\(index)", options: Options(), steps: steps + [Step(time: 0.25)]))
        }
        for index in traces.indices {
            var engine = GestureEngine(); let options = traces[index].options
            engine.nativeTransforms = options.native; engine.tapToDrag = options.tapDrag; engine.tapToClick = options.tapClick
            engine.holdToClick = options.hold; engine.pressureToClick = options.pressure
            engine.threeFingerMode = options.threeDrag ? .drag : .swipe
            var output: [InputPacket] = []; var time = 0.0
            engine.emit = { kind, x, y, fingers in output.append(InputPacket(kind: kind, x: x, y: y, fingers: fingers, time: time)) }
            for step in traces[index].steps {
                time = step.time
                switch step.action {
                case "advance": engine.advance(at: time)
                case "cancel": engine.cancel()
                default: engine.update(step.points.map { TouchPoint(id: $0.id, x: $0.x, y: $0.y, pressure: $0.pressure) }, at: time)
                }
            }
            traces[index].expected = output
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(traces)); FileHandle.standardOutput.write(Data([10]))
    }
}
