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
protocol DisplayWatching: AnyObject {
    func start(onChange: @escaping () -> Void)
    func stop()
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

    /// The user's brightness is saved and waits to be put back.
    var isDimmed: Bool { defaults.object(forKey: Self.previousKey) != nil }

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

/// Runs `DisplayRules` on every sample and does what they say.
@MainActor
final class DisplayController {
    private let reader: DisplayReading
    private let sleeper: DisplaySleeping
    private let dimmer: BuiltinDimmer
    private let watcher: DisplayWatching?
    private var memory = DisplayMemory()
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "Display")

    init(reader: DisplayReading, sleeper: DisplaySleeping, dimmer: BuiltinDimmer, watcher: DisplayWatching? = nil) {
        self.reader = reader
        self.sleeper = sleeper
        self.dimmer = dimmer
        self.watcher = watcher
    }

    /// A brightness that a copy before this one left at zero comes back
    /// first. The rules dim again when that is still right.
    func start(onChange: @escaping () -> Void) {
        if dimmer.isDimmed {
            log.info("putting back the brightness an earlier run left at zero")
            memory.dimmed = !dimmer.restore()
        }
        watcher?.start(onChange: onChange)
    }

    func update(lidClosed: Bool, holding: Bool, enabled: Bool, now: Date) {
        // With the lid open and nothing to put back, nothing is read.
        if !lidClosed, !memory.dimmed, memory.lidClosedAt == nil { return }
        var inputs = reader.read()
        inputs.lidClosed = lidClosed
        inputs.holding = holding
        inputs.brightness = dimmer.level()
        let (actions, next) = DisplayRules.decide(inputs, enabled: enabled, memory: memory, now: now)
        memory = next
        for action in actions {
            log.info("\(String(describing: action).prefix(while: { $0 != "(" }), privacy: .public): \(action.reason, privacy: .public)")
            switch action {
            case .sleepDisplays:
                if !sleeper.sleepDisplays() { log.error("the request for display sleep failed") }
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
        if dimmer.isDimmed { memory.dimmed = !dimmer.restore() }
    }
}
