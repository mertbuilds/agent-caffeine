import Foundation

/// A value that repeats for ever: points at shares of its period, with
/// straight lines between them. Core Animation runs a track in the render
/// server, so a motion costs the app nothing while it runs. `value(at:)`
/// gives the same value for a still picture of any moment.
struct MotionTrack: Equatable {
    var period: TimeInterval
    /// How far the loop is ahead, in periods.
    var lead: Double = 0
    /// From 0 to 1, rising.
    var keyTimes: [Double]
    var values: [Double]

    /// Where the loop is at a time, from 0 to 1.
    func phase(at time: TimeInterval) -> Double {
        let turns = time / period + lead
        return turns - turns.rounded(.down)
    }

    func value(at time: TimeInterval) -> Double {
        value(atPhase: phase(at: time))
    }

    func value(atPhase phase: Double) -> Double {
        guard let next = keyTimes.firstIndex(where: { $0 > phase }) else { return values[values.count - 1] }
        guard next > 0 else { return values[0] }
        let share = (phase - keyTimes[next - 1]) / (keyTimes[next] - keyTimes[next - 1])
        return values[next - 1] + (values[next] - values[next - 1]) * share
    }

    /// The loop starts at a time that is a whole number of periods after
    /// this one, on any clock. Never 0, which Core Animation reads as now.
    var start: TimeInterval {
        let behind = lead - lead.rounded(.down)
        return period * (1 - behind)
    }

    /// A curve as a track: its value at `steps` even shares of the period.
    static func sampled(period: TimeInterval, lead: Double = 0, steps: Int, _ value: (Double) -> Double) -> MotionTrack {
        let keyTimes = (0...steps).map { Double($0) / Double(steps) }
        return MotionTrack(period: period, lead: lead, keyTimes: keyTimes, values: keyTimes.map(value))
    }
}
