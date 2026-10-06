import Foundation

/// A lid angle without steps, from a sensor that gives whole degrees.
///
/// The sensor's value is a stair. The estimate walks to each new value at
/// the speed the lid was measured to have: the size of the step over the
/// time since the step before. At an even speed it arrives at the moment
/// the next step comes, so it moves without a stop and is one step of the
/// sensor behind. It never passes the value the sensor gave, so a lid that
/// stops is not overshot, and it never turns around while the sensor does
/// not.
///
/// One degree back against the last move is noise of a sensor that reads
/// 117, 118, 117. It is left out until the lid is two degrees back.
///
/// Pure: the caller passes the time.
struct LidAngleEstimator: Equatable {
    /// How fast a distance that is more than one step of the sensor is
    /// made up: the time constant, in seconds. A lid that gets faster is
    /// one step and about this long behind.
    static let catchUp: TimeInterval = 0.08
    /// A step is walked in this time at most. It is the speed for a step
    /// with no step before it to measure from: 4 degrees per second for
    /// one degree.
    static let slowestStep: TimeInterval = 0.25
    /// The longest time one update counts for, so a late update does not
    /// jump.
    static let longestUpdate: TimeInterval = 0.05
    /// A step with no step before it starts when it is seen: the time
    /// before it counts as one frame.
    static let firstUpdate: TimeInterval = 1.0 / 120
    /// A step back that is smaller than this is noise.
    static let reversal = 2.0

    /// The estimate, in degrees. Nil before the first value.
    private(set) var angle: Double?
    /// The value of the sensor the estimate walks to.
    private(set) var goal: Double?
    /// 1 when the last step went up, -1 when it went down.
    private var direction = 0.0
    /// Degrees per second, from the steps of the sensor.
    private(set) var speed = 0.0
    /// The size of the last step.
    private var lead = 1.0
    private var steppedAt: Date?
    private var at: Date?

    /// The estimate is not yet at the value of the sensor.
    var isMoving: Bool { angle != goal }

    /// The lid is known to be here, as when it is shut.
    mutating func reset(to value: Double, now: Date) {
        angle = value
        goal = value
        direction = 0
        speed = 0
        lead = 1
        steppedAt = now
        at = now
    }

    /// One reading of the sensor. The same value again and again is what
    /// a sensor that is asked every frame gives.
    @discardableResult
    mutating func update(sample: Double, now: Date) -> Double {
        guard var position = angle, let goal, let last = at else {
            reset(to: sample, now: now)
            return sample
        }
        var passed = min(max(now.timeIntervalSince(last), 0), Self.longestUpdate)
        at = now

        let step = sample - goal
        let way: Double = step > 0 ? 1 : -1
        let turned = direction != 0 && way != direction
        if step != 0, !(turned && abs(step) < Self.reversal) {
            let since = steppedAt.map { now.timeIntervalSince($0) } ?? .infinity
            if !turned, direction != 0, since > 0, since <= Self.slowestStep {
                let measured = abs(step) / since
                speed = speed > 0 ? (speed + measured) / 2 : measured
            } else {
                speed = abs(step) / Self.slowestStep
                passed = min(passed, Self.firstUpdate)
            }
            lead = abs(step)
            direction = way
            steppedAt = now
            self.goal = sample
        }

        let target = self.goal ?? sample
        let gap = target - position
        if gap != 0 {
            let walked = (speed + max(abs(gap) - lead, 0) / Self.catchUp) * passed
            position = walked >= abs(gap) ? target : position + (gap > 0 ? walked : -walked)
            angle = position
        }
        return position
    }
}
