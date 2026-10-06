import Foundation

/// What is known at one reading of the lid angle sensor.
struct LidDimInputs: Equatable {
    /// Degrees between the lid and the keyboard. Nil when the sensor gave
    /// no answer.
    var angle: Double?
    /// Of the built-in display now, 0 to 1. Nil when it cannot be read.
    var brightness: Float?
    /// The user's brightness that is saved to be put back, if any.
    var saved: Float?
    /// Both settings are on.
    var enabled = true
    var sensorAvailable = true
    /// agent caffeine keeps the Mac awake.
    var holding = false
    var externalDisplay = false
    /// What the power root domain says about the lid.
    var clamshellClosed = false
    /// agent caffeine put the displays to sleep and did not wake them yet.
    var slept = false
}

struct LidDimMemory: Equatable {
    enum Phase: Equatable {
        /// The brightness is the user's and is not touched.
        case idle
        /// The brightness follows the angle.
        case fading
        /// The lid is shut and the display is dark.
        case closed
    }

    var phase = Phase.idle
    /// The user's brightness, from when the lid came below 45 degrees.
    var user: Float?
    /// What was set last.
    var written: Float?
    var wroteAt: Date?
    var lastAngle: Double?
    /// When the angle last changed.
    var changedAt: Date?
    /// Since when the sensor gives no answer.
    var silentSince: Date?
    /// The angle without the steps of the sensor. The brightness follows
    /// this one.
    var estimator = LidAngleEstimator()
    var keys = BrightnessKeyDetector()
    /// The lowest angle since the lid last moved, and since when.
    var restLow: Double?
    var restSince: Date?
    /// The lid rests half open: the brightness is the user's.
    var released = false
    /// 0 to 1, how far the brightness is back at the user's value.
    var release: Double = 0
    var at: Date?

    /// For a sensor that starts again: what the lid did before is unknown.
    func forgettingMotion() -> LidDimMemory {
        var next = self
        next.lastAngle = nil
        next.changedAt = nil
        next.silentSince = nil
        next.estimator = LidAngleEstimator()
        next.restLow = nil
        next.restSince = nil
        next.at = nil
        return next
    }
}

enum LidDimAction: Equatable {
    /// The user's brightness is saved, so a start after a crash can put
    /// it back.
    case save(Float)
    case set(Float)
    /// The user's brightness comes back and the saved value is removed.
    case restore(reason: String)
    case sleepDisplays
    case wakeDisplays
}

/// How often the sensor is asked.
enum LidPoll: Equatable {
    case slow
    case fast

    var interval: TimeInterval {
        switch self {
        case .slow: return 0.5
        case .fast: return 1.0 / 120
        }
    }
}

struct LidDimStep: Equatable {
    var actions: [LidDimAction] = []
    var memory: LidDimMemory
    /// The brightness after this step. Nil when it is not touched.
    var target: Float?
    var poll = LidPoll.slow
    /// For the log: a fade that starts, reaches closed or ends.
    var notes: [String] = []
}

/// The built-in display gets darker as the lid closes and brighter as it
/// opens, while agent caffeine keeps the Mac awake. Pure: the caller keeps
/// the memory and passes the time.
///
/// At 45 degrees and above the brightness is the user's. From 45 degrees
/// down to the closed angle it is the user's brightness times `curve`. At
/// the closed angle, or when the lid switch says closed, it is zero, and
/// without an external display the displays also go to sleep. The way up
/// is the same curve.
///
/// The sensor gives whole degrees, and one degree is up to 3.6 percent of
/// the brightness: a stair the eye sees as flicker. So the curve is fed
/// from `LidAngleEstimator`, which has no steps. The sensor's own value
/// decides only where the fade starts and ends.
///
/// A lid that rests between 20 and 45 degrees is in use, so after 1.5
/// seconds the user's brightness comes back. It fades again when the lid
/// moves down.
enum LidDimming {
    static let fadeStart = 45.0
    /// At or below this the lid counts as shut. The sensor gives whole
    /// degrees.
    static let closedAngle = 3.0
    /// Below this angle the sensor is asked 120 times a second while the
    /// lid moves.
    static let fastBelow = 70.0
    /// After this long without a change of the angle the lid is steady.
    static let steadyAfter: TimeInterval = 2
    static let restAbove = 20.0
    static let restAfter: TimeInterval = 1.5
    /// A lid that came up by this much moved. One degree is noise.
    static let restSlack = 2.0
    /// How long the way back to the user's brightness takes for a lid that
    /// rests, and the way down again when it moves.
    static let releaseTime: TimeInterval = 0.3
    static let resumeTime: TimeInterval = 0.15
    /// A sensor that gives no answer for this long is gone. It is asked
    /// fast in that time, so more than one answer is missed.
    static let sensorTimeout: TimeInterval = 0.5
    /// A change smaller than this is not written.
    static let minChange: Float = 0.001
    /// A brightness key counts after the lid and agent caffeine were quiet
    /// for this long. See `BrightnessKeyDetector`.
    static let userQuiet: TimeInterval = 0.3
    /// The longest time one step counts for, so a late step does not jump.
    static let longestStep: TimeInterval = 0.05

    /// The share of the user's brightness at an angle, 0 to 1. Smoothstep:
    /// it leaves 45 degrees and reaches the closed angle with no kink. The
    /// brightness scale of macOS is perceptual already, so no gamma is
    /// put on top.
    static func curve(_ angle: Double) -> Double {
        let t = min(max((angle - closedAngle) / (fadeStart - closedAngle), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func decide(_ inputs: LidDimInputs, memory: LidDimMemory, now: Date) -> LidDimStep {
        var memory = memory
        let passed = memory.at.map { min(max(now.timeIntervalSince($0), 0), longestStep) } ?? 0
        memory.at = now
        guard inputs.enabled else { return end(memory, inputs, reason: "the setting is off") }
        guard inputs.sensorAvailable else { return end(memory, inputs, reason: "this Mac has no lid angle sensor") }
        guard let angle = inputs.angle else {
            if memory.phase == .idle { return LidDimStep(memory: memory.forgettingMotion()) }
            let since = memory.silentSince ?? now
            memory.silentSince = since
            let silent = now.timeIntervalSince(since)
            if silent >= sensorTimeout || silent < 0 { return end(memory, inputs, reason: "the lid angle sensor stopped answering") }
            return LidDimStep(memory: memory, target: memory.written, poll: .fast)
        }

        let previous = memory.lastAngle
        if previous != angle { memory.changedAt = now }
        memory.lastAngle = angle
        memory.silentSince = nil
        // A shut lid is at the closed angle, whatever the sensor reads
        // under it: the way up starts from black.
        let shut = angle <= closedAngle || inputs.clamshellClosed && angle < fadeStart
        if shut {
            memory.estimator.reset(to: closedAngle, now: now)
        } else {
            memory.estimator.update(sample: angle, now: now)
        }
        let smooth = memory.estimator.angle ?? angle
        let walking = memory.estimator.isMoving
        var step = LidDimStep(memory: memory)
        // Not while the lid switch says closed: a sensor that reads a few
        // degrees for a shut lid must not wake the displays under it.
        if angle > closedAngle, inputs.slept, !inputs.clamshellClosed { step.actions.append(.wakeDisplays) }
        let moving = memory.changedAt.map { now.timeIntervalSince($0) < steadyAfter } ?? false

        if angle >= fadeStart || shut {
            memory.restLow = nil
            memory.restSince = nil
            memory.released = false
            memory.release = 0
        }
        if angle >= fadeStart {
            if memory.phase != .idle {
                step.actions.append(.restore(reason: "the lid is open"))
                step.notes.append("the lid is open at \(Int(angle)) degrees: the brightness is back")
                memory = idle(memory)
            }
            step.memory = memory
            step.poll = angle < fastBelow && moving ? .fast : .slow
            return step
        }
        if shut {
            step.poll = moving ? .fast : .slow
            if !inputs.holding, !inputs.externalDisplay {
                // The Mac goes to sleep, and wakes with its own brightness.
                if memory.phase != .idle {
                    step.actions.append(.restore(reason: "agent caffeine no longer keeps the Mac awake"))
                    step.notes.append("the fade ends: agent caffeine no longer keeps the Mac awake")
                    memory = idle(memory)
                }
                step.memory = memory
                return step
            }
            if memory.phase == .idle {
                guard inputs.holding, let user = inputs.saved ?? inputs.brightness, user > DisplayRules.darkLevel else {
                    step.memory = memory
                    return step
                }
                memory.user = user
                step.actions.append(.save(user))
            }
            if memory.phase != .closed {
                if memory.written != 0 { step.actions.append(.set(0)) }
                if !inputs.externalDisplay { step.actions.append(.sleepDisplays) }
                step.notes.append("the lid is shut: the built-in display is off")
                memory.written = 0
                memory.wroteAt = now
                memory.keys.wrote(0, now: now)
                memory.phase = .closed
            }
            step.memory = memory
            step.target = 0
            return step
        }

        // Between the closed angle and 45 degrees.
        if let low = memory.restLow {
            if angle < low {
                memory.restLow = angle
                memory.restSince = now
                memory.released = false
            } else if angle >= low + restSlack {
                memory.restLow = angle
                memory.restSince = now
            }
        } else {
            memory.restLow = angle
            memory.restSince = now
            // A lid that was not seen on its way down rests here already.
            if previous == nil, memory.phase == .idle {
                memory.released = true
                memory.release = 1
            }
        }

        if memory.phase == .idle {
            guard !memory.released, inputs.holding, let user = inputs.saved ?? inputs.brightness, user > DisplayRules.darkLevel else {
                step.memory = memory
                step.poll = moving ? .fast : .slow
                return step
            }
            memory.user = user
            memory.written = inputs.brightness ?? user
            memory.wroteAt = nil
            memory.keys.wrote(inputs.brightness ?? user, now: now)
            memory.phase = .fading
            step.actions.append(.save(user))
            step.notes.append("the lid closes below \(Int(fadeStart)) degrees: the built-in display fades")
        } else if memory.phase == .closed {
            memory.phase = .fading
        }
        if !memory.released, angle >= restAbove, let since = memory.restSince, now.timeIntervalSince(since) >= restAfter {
            memory.released = true
            step.notes.append("the lid rests at \(Int(angle)) degrees: the brightness is back")
        }

        // A brightness key, with the lid at rest and the user's brightness
        // on. What moves the brightness while it fades is not the user: the
        // fade itself, or auto-brightness under a lid that covers the light
        // sensor. The fade stays on the value from 45 degrees.
        let lidQuiet = memory.changedAt.map { now.timeIntervalSince($0) >= userQuiet } ?? true
        let writesQuiet = memory.wroteAt.map { now.timeIntervalSince($0) >= userQuiet } ?? true
        let rested = memory.released && memory.release >= 1 && !walking && lidQuiet && writesQuiet
        if let read = inputs.brightness, read > DisplayRules.darkLevel, let user = memory.keys.read(read, rested: rested, now: now) {
            memory.user = user
            memory.written = user
            step.actions.append(.save(user))
        }

        memory.release = min(max(memory.release + (memory.released ? passed / releaseTime : -passed / resumeTime), 0), 1)
        let settling = memory.released ? memory.release < 1 : memory.release > 0
        let base = curve(smooth)
        let factor = base + (1 - base) * memory.release
        let user = memory.user ?? 0
        let target = user * Float(factor)
        // The first step up from black is always written.
        if abs(target - (memory.written ?? -1)) > minChange || memory.written == 0 && target > 0 {
            step.actions.append(.set(target))
            memory.written = target
            memory.wroteAt = now
            memory.keys.wrote(target, now: now)
        }
        step.memory = memory
        step.target = memory.written
        step.poll = moving || settling || walking ? .fast : .slow
        return step
    }

    /// The fade is over. Under a closed lid the display stays dark and
    /// `DisplayRules` goes on from there.
    private static func end(_ memory: LidDimMemory, _ inputs: LidDimInputs, reason: String) -> LidDimStep {
        var next = LidDimMemory()
        next.at = memory.at
        guard memory.phase != .idle else { return LidDimStep(memory: next) }
        if inputs.clamshellClosed {
            return LidDimStep(memory: next, target: memory.written, notes: ["the fade ends under the closed lid: \(reason)"])
        }
        return LidDimStep(actions: [.restore(reason: reason)], memory: next, notes: ["the fade ends and the brightness is back: \(reason)"])
    }

    private static func idle(_ memory: LidDimMemory) -> LidDimMemory {
        var next = memory
        next.phase = .idle
        next.user = nil
        next.written = nil
        next.wroteAt = nil
        return next
    }
}
