import Foundation
import os

/// The system sounds the chime can be. The raw value is the name `NSSound`
/// knows it by: the files in /System/Library/Sounds have had these names
/// since before macOS 13. All are soft, and none is the alert sound.
enum LidChimeSound: String, Codable, CaseIterable, Identifiable {
    /// A short, bright tap. About half a second.
    case tink = "Tink"
    case bottle = "Bottle"
    case purr = "Purr"
    /// Rings for longer than a second.
    case glass = "Glass"

    var id: String { rawValue }
}

/// Plays a sound, so a test and the smoke test can count the sounds and
/// make none.
@MainActor
protocol LidChimePlaying: AnyObject {
    /// False when this Mac does not have the sound.
    @discardableResult
    func play(_ sound: LidChimeSound) -> Bool
}

/// What the Mac does at one moment, for the chime.
struct LidChimeInputs: Equatable {
    var lidClosed = false
    /// "Play a sound when you close the lid and your Mac stays awake".
    var enabled = true
    /// Agent Caffeine keeps the Mac awake: the decision holds and the
    /// power assertions are taken.
    var holding = false
    var onBattery = false
    /// The decision asks for the sleep flag. Off with "Stay awake with the
    /// lid closed on battery" off.
    var flagWanted = false
    var helperEnabled = false
    /// The helper confirmed that the sleep flag is set.
    var flagConfirmed = false
}

/// The sound that says "the lid is closed and your Mac stays awake". It is
/// a promise, so it plays only when that is true at that moment. Silence
/// means the Mac sleeps. Pure: the caller passes what the Mac does and the
/// time, in seconds on a clock that only moves forward.
///
/// Only the lid that goes from open to closed counts. The first look after
/// the launch and after a sleep is no change, and a display that comes or
/// goes while the lid stays closed is none either. A Mac without a lid
/// never reads as closed.
///
/// On wall power the power assertions keep a Mac with a closed lid awake,
/// with or without an external display (docs/research/02-keep-awake.md),
/// so the hold alone is enough there. On battery only the sleep flag of
/// the helper does, and the helper has to confirm it. The flag is asked
/// for when the hold starts, so its answer can come a moment after the
/// lid: the chime waits for it for `confirmationWait` and stays silent
/// when it does not come.
struct LidChime: Equatable {
    /// How long a closed lid waits for the helper to confirm the flag.
    static let confirmationWait: TimeInterval = 1.5
    /// A lid that bounces gives one chime.
    static let minimumGap: TimeInterval = 2

    enum Silence: String, Equatable {
        case switchedOff = "the sound is turned off"
        case notHolding = "Agent Caffeine does not keep the Mac awake"
        case lidSettingOff = "on battery, and staying awake with the lid closed is turned off"
        case helperNotSetUp = "on battery, and the helper is not set up"
        case flagNotConfirmed = "on battery, and the helper did not confirm the sleep flag in time"
        case reopened = "the lid opened before the helper confirmed the sleep flag"
        case tooSoon = "the last chime was a moment ago"
    }

    enum Verdict: Equatable {
        case chime
        /// On battery, and the helper's answer is still to come.
        case wait
        case silent(Silence)
    }

    /// What became of a lid that closed.
    enum Outcome: Equatable {
        case played
        case silent(Silence)

        /// For the log. No names and no paths.
        var logLine: String {
            switch self {
            case .played: return "lid closed: the chime played"
            case .silent(let why): return "lid closed: no chime, \(why.rawValue)"
            }
        }
    }

    /// Nil before the first look, and after a sleep.
    private var lidClosed: Bool?
    /// The lid closed at this time and waits for the helper's answer.
    private var waitingSince: TimeInterval?
    private var lastChimeAt: TimeInterval?

    var isWaiting: Bool { waitingSince != nil }

    /// Whether the Mac stays awake with the lid closed because of Agent
    /// Caffeine, at this moment.
    static func verdict(_ inputs: LidChimeInputs) -> Verdict {
        guard inputs.enabled else { return .silent(.switchedOff) }
        guard inputs.holding else { return .silent(.notHolding) }
        guard inputs.onBattery else { return .chime }
        if inputs.flagWanted, inputs.flagConfirmed { return .chime }
        guard inputs.flagWanted else { return .silent(.lidSettingOff) }
        return inputs.helperEnabled ? .wait : .silent(.helperNotSetUp)
    }

    /// The Mac slept, so what the lid did in between is not known.
    mutating func forget() {
        lidClosed = nil
        waitingSince = nil
    }

    /// - Returns: what became of a lid that closed, once. Nil when the lid
    ///   did not close and nothing waits, and while it still waits.
    mutating func observe(_ inputs: LidChimeInputs, now: TimeInterval) -> Outcome? {
        let was = lidClosed
        lidClosed = inputs.lidClosed
        guard inputs.lidClosed else {
            guard waitingSince != nil else { return nil }
            waitingSince = nil
            return .silent(.reopened)
        }
        let closedAt: TimeInterval
        if let waitingSince {
            closedAt = waitingSince
        } else if was == false {
            closedAt = now
        } else {
            return nil
        }
        waitingSince = nil
        switch Self.verdict(inputs) {
        case .silent(let why):
            return .silent(why)
        case .wait:
            guard now - closedAt < Self.confirmationWait else { return .silent(.flagNotConfirmed) }
            waitingSince = closedAt
            return nil
        case .chime:
            // An answer that comes after the wait is too late to be told.
            guard now - closedAt <= Self.confirmationWait else { return .silent(.flagNotConfirmed) }
            if let lastChimeAt, now - lastChimeAt < Self.minimumGap { return .silent(.tooSoon) }
            lastChimeAt = now
            return .played
        }
    }
}

/// Runs `LidChime` and plays what it decides. Every lid that closes is in
/// the log with what became of it, so a test by hand can be judged.
@MainActor
final class LidChimer {
    private let player: LidChimePlaying?
    private var chime = LidChime()
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "LidChime")

    /// Nil plays nothing.
    init(player: LidChimePlaying?) {
        self.player = player
    }

    /// The lid closed and the helper's answer is still to come: the owner
    /// looks again soon.
    var isWaiting: Bool { chime.isWaiting }

    func forget() {
        chime.forget()
    }

    /// - Parameter detail: what the decision says, for the log of a lid
    ///   that closed with no chime.
    @discardableResult
    func observe(_ inputs: LidChimeInputs, sound: LidChimeSound, detail: String = "", now: TimeInterval) -> LidChime.Outcome? {
        guard let outcome = chime.observe(inputs, now: now) else { return nil }
        switch outcome {
        case .played:
            let played = player?.play(sound) ?? false
            log.notice("\(outcome.logLine, privacy: .public) (\(sound.rawValue, privacy: .public)\(played ? "" : ", this Mac does not have the sound", privacy: .public))")
        case .silent(.notHolding):
            log.notice("\(outcome.logLine, privacy: .public) (\(detail, privacy: .public))")
        case .silent:
            log.notice("\(outcome.logLine, privacy: .public)")
        }
        return outcome
    }

    /// "Play" in Preferences.
    func preview(_ sound: LidChimeSound) {
        player?.play(sound)
    }
}
