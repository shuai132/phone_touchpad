import Foundation

struct TouchFrame {
    var time: Double
    var points: [TouchPoint]
}
struct TouchSample {
    var time: Double
    var x: Double
    var y: Double
    var pressure: Double? = nil
}
struct TouchTrajectory {
    var id: Int
    var samples: [TouchSample]
}

/// Replays recorded coalesced input at common timestamps for every active finger.
/// Interpolation uses known samples only; no predicted or future touch data is requested.
/// Updating one finger at a time would incorrectly turn parallel scrolling into a pinch.
enum TouchFrameSampler {
    static func frames(from previous: TouchFrame?, to latest: TouchFrame, trajectories: [TouchTrajectory]) -> [TouchFrame] {
        guard latest.time.isFinite, latest.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        if let previous, latest.time < previous.time { return [] }
        guard let previous, previous.time < latest.time,
              Set(previous.points.map(\.id)) == Set(latest.points.map(\.id)), !latest.points.isEmpty else {
            return [latest]
        }
        var tracks: [Int: [TouchSample]] = [:]
        var times: Set<Double> = [latest.time]
        for point in latest.points {
            guard let start = previous.points.first(where: { $0.id == point.id }) else { return [latest] }
            var byTime: [Double: TouchSample] = [:]
            for trajectory in trajectories where trajectory.id == point.id {
                for sample in trajectory.samples where sample.time.isFinite && sample.x.isFinite && sample.y.isFinite && sample.time > previous.time && sample.time < latest.time {
                    byTime[sample.time] = sample
                    times.insert(sample.time)
                }
            }
            byTime[previous.time] = TouchSample(time: previous.time, x: start.x, y: start.y, pressure: start.pressure)
            byTime[latest.time] = TouchSample(time: latest.time, x: point.x, y: point.y, pressure: point.pressure)
            tracks[point.id] = byTime.values.sorted { $0.time < $1.time }
        }
        return times.sorted().map { time in
            let points = latest.points.map { point -> TouchPoint in
                guard let track = tracks[point.id], let right = track.firstIndex(where: { $0.time >= time }) else { return point }
                if right == 0 { return TouchPoint(id: point.id, x: track[0].x, y: track[0].y, pressure: track[0].pressure) }
                let a = track[right - 1], b = track[right]
                let progress = (time - a.time) / (b.time - a.time)
                let pressure: Double?
                if let ap = a.pressure, let bp = b.pressure, ap.isFinite, bp.isFinite {
                    pressure = ap + (bp - ap) * progress
                } else { pressure = nil }
                return TouchPoint(id: point.id, x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress, pressure: pressure)
            }
            return TouchFrame(time: time, points: points)
        }
    }
}
