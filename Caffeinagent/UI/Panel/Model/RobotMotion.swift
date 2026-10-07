import CoreGraphics
import Foundation

/// How the steam moves. Each wisp grows out of the coffee, stretches and
/// fades, in a loop of its own phase. Two copies of each wisp run half a
/// loop apart, so the steam never stops: one fades in while the other
/// fades out.
enum RobotSteamMotion {
    static let period: TimeInterval = 3.6
    static let swayPeriod: TimeInterval = 4.6
    /// How far each wisp is ahead of the first. The two wisps of the icon
    /// come first.
    static let lags: [Double] = [0, 0.37, 0.71]
    static let copies = 2
    /// How far the top of a wisp leans, as a share of the picture.
    static let lean: CGFloat = 0.007
    /// Where the icon shows a wisp. A wisp that stands still is here.
    static let restPhase = 0.5

    /// How tall the wisp is at a phase, as a share of the icon's.
    static func stretch(_ phase: Double) -> Double {
        0.6 + 0.8 * phase
    }

    /// How far it has left the coffee, as a share of the picture.
    static func lift(_ phase: Double) -> Double {
        0.05 * max(0, phase - 0.5)
    }

    /// 0 where the wisp leaves the coffee and where it is gone.
    static func strength(_ phase: Double) -> Double {
        pow(sin(.pi * phase), 2)
    }

    private static func lead(wisp: Int, copy: Int) -> Double {
        lags[wisp] + Double(copy) / Double(copies)
    }

    static func stretchTrack(wisp: Int, copy: Int) -> MotionTrack {
        MotionTrack(period: period, lead: lead(wisp: wisp, copy: copy), keyTimes: [0, 1], values: [stretch(0), stretch(1)])
    }

    static func liftTrack(wisp: Int, copy: Int) -> MotionTrack {
        MotionTrack(period: period, lead: lead(wisp: wisp, copy: copy), keyTimes: [0, 0.5, 1], values: [lift(0), lift(0.5), lift(1)])
    }

    static func strengthTrack(wisp: Int, copy: Int) -> MotionTrack {
        .sampled(period: period, lead: lead(wisp: wisp, copy: copy), steps: 24, strength)
    }

    /// -1 to 1: how far the top leans.
    static func swayTrack(wisp: Int) -> MotionTrack {
        .sampled(period: swayPeriod, lead: Double(wisp) * 1.7 / (2 * .pi), steps: 24) { sin(2 * .pi * $0) }
    }

    /// The phase of a copy that stands still: the first one is the wisp
    /// of the icon, the second one is not there.
    static func restPhase(copy: Int) -> Double {
        copy == 0 ? restPhase : 0
    }
}

/// The breath of the antenna's light.
enum RobotAntennaPulse {
    static let period: TimeInterval = 3.1
    /// The middle of the breath, where a light that does not breathe stays.
    static let rest = 0.65

    /// Between 0.3 and 1, once in about three seconds.
    static let track = MotionTrack.sampled(period: period, steps: 24) { rest + 0.35 * sin(2 * .pi * $0) }
}

/// The letters that drift up from a sleeping robot.
enum RobotSnoozeMotion {
    static let period: TimeInterval = 4.4
    static let letters = 2
    /// Where each letter is when it stands still.
    static let restPhases: [Double] = [0.62, 0.3]

    static func strengthTrack(letter: Int) -> MotionTrack {
        .sampled(period: period, lead: lead(letter), steps: 24) { sin(.pi * $0) }
    }

    /// The way of a letter, from 0 to 1.
    static func phaseTrack(letter: Int) -> MotionTrack {
        MotionTrack(period: period, lead: lead(letter), keyTimes: [0, 1], values: [0, 1])
    }

    /// The top leading corner of a letter, as a share of the picture.
    static func place(letter: Int, phase: Double) -> CGPoint {
        CGPoint(x: 0.77 + 0.05 * phase - Double(letter) * 0.07, y: 0.17 - 0.11 * phase + Double(letter) * 0.09)
    }

    /// The size of a letter, as a share of the picture.
    static func size(letter: Int) -> CGFloat {
        letter == 0 ? 0.13 : 0.095
    }

    private static func lead(_ letter: Int) -> Double {
        Double(letter) * 0.45
    }
}

/// The ring round an agent's mark: an arc that sweeps round for work, a
/// whole ring that breathes for an agent that waits.
enum RingMotion {
    static let sweepPeriod: TimeInterval = 1.4
    static let pulsePeriod: TimeInterval = 2
    /// The arc, as a share of the outline.
    static let arc: CGFloat = 0.75
    /// Where the arc starts when it stands still.
    static let restTurn = 0.125

    /// Where the arc starts, as a share of the outline.
    static let turn = MotionTrack(period: sweepPeriod, keyTimes: [0, 1], values: [0, 1])
    /// Between 0.4 and 1.
    static let pulse = MotionTrack.sampled(period: pulsePeriod, steps: 24) { 0.7 + 0.3 * sin(2 * .pi * $0) }
}
