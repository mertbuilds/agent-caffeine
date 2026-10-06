import Foundation
import os

/// What the displays are doing. `brightness` of `DisplayInputs` is not
/// filled here: it comes from the dimmer.
protocol DisplayReading {
    func read() -> DisplayInputs
}

/// Puts all displays to sleep, as the display sleep timer does.
protocol DisplaySleeping {
    /// False when the request could not be made.
    func sleepDisplays() -> Bool
    /// As a key press does: displays that sleep come on.
    func wakeDisplays()
}

/// One way to read and set the brightness of the built-in display.
protocol BuiltinBrightness {
    var name: String { get }
    /// 0 to 1. Nil when this way cannot read it.
    func level() -> Float?
    /// False when this way refused.
    func set(_ level: Float) -> Bool
}

/// Tells that the lid or the displays changed, before the next sample.
/// Both call on the main thread.
protocol DisplayWatching: AnyObject {
    /// `lidClosed` is nil when the list of displays changed.
    func start(onChange: @escaping (_ lidClosed: Bool?) -> Void)
    func stop()
}

/// The lid angle sensor of this Mac.
protocol LidAngleReading: AnyObject {
    /// False on a Mac without the sensor.
    var isAvailable: Bool { get }
    /// Opens the sensor. `onPush` gets the angles the sensor sends by
    /// itself, on the main thread.
    func start(onPush: @escaping (Double) -> Void)
    func stop()
    /// Degrees between the lid and the keyboard. Nil when the sensor gave
    /// no answer.
    func angle() -> Double?
}

/// Calls again and again on the main thread.
protocol LidTicking: AnyObject {
    /// Replaces the timer before it. Nil stops.
    func tick(every interval: TimeInterval?, _ work: @escaping () -> Void)
}

/// Sets the brightness of the built-in display to zero and puts the user's
/// value back. The value is saved before the display goes dark, so a copy
/// of the app that starts after a crash can put it back: nobody opens the
/// lid to a black screen.
final class BuiltinDimmer {
    static let previousKey = "DisplayDim.previousBrightness"
    static let methodKey = "DisplayDim.method"

    private let methods: [BuiltinBrightness]
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "Display")

    init(methods: [BuiltinBrightness], defaults: UserDefaults) {
        self.methods = methods
        self.defaults = defaults
    }

    /// The way a write was seen to work with, in this run.
    private var trusted: BuiltinBrightness?

    /// The user's brightness is saved and waits to be put back.
    var isDimmed: Bool { defaults.object(forKey: Self.previousKey) != nil }

    /// The user's brightness that waits to be put back.
    var saved: Float? { (defaults.object(forKey: Self.previousKey) as? Double).map(Float.init) }

    /// Before a fade: `restore` puts this value back.
    func save(_ level: Float) {
        defaults.set(Double(level), forKey: Self.previousKey)
    }

    /// One step of a fade. The saved value is not touched. False when no
    /// way took the value.
    func set(_ level: Float) -> Bool {
        if let trusted { return trusted.set(level) }
        for method in ordered {
            let before = method.level()
            guard method.set(level) else { continue }
            guard let before, abs(before - level) > 0.01, let after = method.level() else { return true }
            // A way that says yes and changes nothing did not work.
            guard abs(after - level) < abs(before - level) else { continue }
            trusted = method
            defaults.set(method.name, forKey: Self.methodKey)
            return true
        }
        return false
    }

    /// From the first way that can read it.
    func level() -> Float? {
        ordered.lazy.compactMap { $0.level() }.first
    }

    /// The way that worked last comes first.
    private var ordered: [BuiltinBrightness] {
        guard let name = defaults.string(forKey: Self.methodKey), let index = methods.firstIndex(where: { $0.name == name }) else { return methods }
        return [methods[index]] + methods[..<index] + methods[(index + 1)...]
    }

    /// True when the display is dark now. The value that is saved is the
    /// one from before the first dimming, also when the brightness came up
    /// again in between.
    func dim() -> Bool {
        let wasDimmed = isDimmed
        if !wasDimmed {
            guard let previous = level() else {
                log.info("the built-in display was not dimmed: its brightness cannot be read")
                return false
            }
            guard previous > DisplayRules.darkLevel else { return true }
            defaults.set(Double(previous), forKey: Self.previousKey)
        }
        for method in ordered where method.set(0) {
            // A way that says yes and changes nothing did not work.
            if let now = method.level(), now > DisplayRules.darkLevel { continue }
            defaults.set(method.name, forKey: Self.methodKey)
            log.info("the built-in display was dimmed with \(method.name, privacy: .public)")
            return true
        }
        log.error("no way to dim the built-in display worked")
        // Whatever a way changed without saying so is put back.
        if !wasDimmed { _ = restore() }
        return false
    }

    /// True when nothing is left to put back.
    func restore() -> Bool {
        guard let previous = defaults.object(forKey: Self.previousKey) as? Double else { return true }
        let wanted = Float(previous)
        for method in ordered where method.set(wanted) {
            if let now = method.level(), abs(now - wanted) > 0.05, now <= DisplayRules.darkLevel { continue }
            defaults.removeObject(forKey: Self.previousKey)
            log.info("the brightness of the built-in display was put back with \(method.name, privacy: .public)")
            return true
        }
        log.error("the brightness of the built-in display could not be put back")
        return false
    }
}

/// Runs `DisplayRules` on every sample and at once when the lid or the
/// displays change, and `LidDimming` on every reading of the lid angle.
@MainActor
final class DisplayController {
    private struct Wanted {
        var lidClosed = false
        var holding = false
        var enabled = false
        var fade = false
    }

    private let reader: DisplayReading
    private let sleeper: DisplaySleeping
    private let dimmer: BuiltinDimmer
    private let watcher: DisplayWatching?
    private let lid: LidAngleReading?
    private let ticker: LidTicking?
    private let clock: () -> Date
    private var memory = DisplayMemory()
    private var fade = LidDimMemory()
    private var wanted = Wanted()
    /// The sensor is open and asked.
    private var armed = false
    private var poll: LidPoll?
    /// agent caffeine put the displays to sleep and did not wake them yet.
    private var slept = false
    private var external: (value: Bool, at: Date)?
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "Display")

    init(
        reader: DisplayReading, sleeper: DisplaySleeping, dimmer: BuiltinDimmer, watcher: DisplayWatching? = nil,
        lid: LidAngleReading? = nil, ticker: LidTicking? = nil, clock: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.sleeper = sleeper
        self.dimmer = dimmer
        self.watcher = watcher
        self.lid = lid
        self.ticker = ticker
        self.clock = clock
    }

    /// False on a Mac without a lid angle sensor: the display then goes
    /// dark when the lid is closed, with no fade.
    var hasLidAngleSensor: Bool { lid?.isAvailable ?? false }

    /// A brightness that a copy before this one left at zero comes back
    /// first. The rules dim again when that is still right.
    func start(onChange: @escaping () -> Void) {
        if dimmer.isDimmed {
            log.info("putting back the brightness an earlier run left dark")
            memory.dimmed = !dimmer.restore()
        }
        watcher?.start { [weak self] lidClosed in
            MainActor.assumeIsolated {
                // The display is dealt with here and now. The sample that
                // follows is for the rest of the app.
                self?.changed(lidClosed: lidClosed)
                onChange()
            }
        }
    }

    /// `fade` is the setting "Dim the display as the lid closes".
    func update(lidClosed: Bool, holding: Bool, enabled: Bool, fade wantsFade: Bool = false, now: Date) {
        wanted = Wanted(lidClosed: lidClosed, holding: holding, enabled: enabled, fade: wantsFade)
        external = nil
        arm()
        // With a fade, the angle says when the displays wake.
        if !lidClosed, slept, !armed {
            sleeper.wakeDisplays()
            slept = false
        }
        // With the lid open and nothing to put back, nothing is read.
        if !lidClosed, !memory.dimmed, memory.lidClosedAt == nil { return }
        var inputs = reader.read()
        inputs.lidClosed = lidClosed
        inputs.holding = holding
        inputs.brightness = dimmer.level()
        let (actions, next) = DisplayRules.decide(inputs, enabled: enabled, memory: memory, now: now)
        memory = next
        for action in actions {
            // While the brightness follows the angle, the fade puts it back.
            if case .restoreBuiltin = action, fade.phase != .idle { continue }
            log.info("\(String(describing: action).prefix(while: { $0 != "(" }), privacy: .public): \(action.reason, privacy: .public)")
            switch action {
            case .sleepDisplays:
                sleep()
            case .dimBuiltin:
                memory.dimFailures = dimmer.dim() ? 0 : memory.dimFailures + 1
                memory.dimmed = dimmer.isDimmed
            case .restoreBuiltin:
                // One that fails is tried again on the next sample.
                memory.dimmed = !dimmer.restore()
            }
        }
    }

    /// At quit: the user's brightness comes back.
    func stop() {
        watcher?.stop()
        disarm()
        fade = LidDimMemory()
        if dimmer.isDimmed { memory.dimmed = !dimmer.restore() }
    }

    // MARK: The lid angle

    private func changed(lidClosed: Bool?) {
        update(lidClosed: lidClosed ?? wanted.lidClosed, holding: wanted.holding, enabled: wanted.enabled, fade: wanted.fade, now: clock())
    }

    /// The sensor is asked only while a fade can start or is under way.
    private func arm() {
        guard let lid, lid.isAvailable else { return }
        let canStart = wanted.enabled && wanted.fade && wanted.holding
        if canStart, !armed {
            armed = true
            fade = fade.forgettingMotion()
            lid.start { [weak self] angle in
                MainActor.assumeIsolated { self?.step(angle: angle) }
            }
        }
        guard armed else { return }
        step(angle: lid.angle())
        if !canStart, fade.phase == .idle { disarm() }
    }

    private func disarm() {
        guard armed else { return }
        armed = false
        poll = nil
        ticker?.tick(every: nil) {}
        lid?.stop()
    }

    private func step(angle: Double?) {
        guard armed else { return }
        let now = clock()
        var inputs = LidDimInputs(
            angle: angle, enabled: wanted.enabled && wanted.fade, holding: wanted.holding, clamshellClosed: wanted.lidClosed, slept: slept
        )
        // With the lid wide open and no fade, nothing else is read.
        if fade.phase != .idle || angle.map({ $0 < LidDimming.fadeStart }) ?? false {
            inputs.brightness = dimmer.level()
            inputs.saved = dimmer.saved
            inputs.externalDisplay = externalDisplay(now: now)
        }
        let before = fade
        let result = LidDimming.decide(inputs, memory: fade, now: now)
        fade = result.memory
        for note in result.notes { log.info("\(note, privacy: .public)") }
        for action in result.actions {
            switch action {
            case .save(let level):
                dimmer.save(level)
            case .set(let level):
                if !dimmer.set(level) {
                    // Tried again at the next reading.
                    fade.written = before.written
                    fade.factor = before.factor
                    fade.wroteAt = before.wroteAt
                }
            case .restore:
                // One that fails is tried again on the next sample.
                _ = dimmer.restore()
            case .sleepDisplays:
                sleep()
            case .wakeDisplays:
                sleeper.wakeDisplays()
                slept = false
            }
        }
        memory.dimmed = dimmer.isDimmed
        if result.poll != poll {
            poll = result.poll
            ticker?.tick(every: result.poll.interval) { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func tick() {
        guard armed, let lid else { return }
        step(angle: lid.angle())
    }

    private func sleep() {
        if sleeper.sleepDisplays() {
            slept = true
        } else {
            log.error("the request for display sleep failed")
        }
    }

    /// Read at most twice a second: a fade asks 60 times a second.
    private func externalDisplay(now: Date) -> Bool {
        if let external, abs(now.timeIntervalSince(external.at)) < 0.5 { return external.value }
        let value = reader.read().externalDisplay
        external = (value, now)
        return value
    }
}
