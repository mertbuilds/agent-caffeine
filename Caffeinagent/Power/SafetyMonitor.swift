import Foundation

enum SafetyStop: Equatable {
    case batteryLow(percent: Int)
    /// On power, and the battery still fell to the floor: the charger gives
    /// less than the Mac uses.
    case weakCharger(percent: Int)
    case tooHot
}

extension SafetyStop {
    /// The text of the notification that tells the user why the Mac slept.
    var notificationText: String {
        switch self {
        case .batteryLow(let percent): return "Agent Caffeine let your Mac sleep because the battery is at \(PanelText.percent(percent))"
        case .weakCharger(let percent):
            return "Agent Caffeine let your Mac sleep because your charger is too weak and the battery is at \(PanelText.percent(percent))"
        case .tooHot: return "Agent Caffeine let your Mac sleep because it got too hot"
        }
    }

    /// The stop to tell the user about, nil for none. A stop is told once,
    /// when it begins, and only when it ended a hold. A stop that goes on,
    /// with a new battery level or as heat after low battery, is the same stop.
    static func toAnnounce(previous: SafetyStop?, current: SafetyStop?, wasHolding: Bool) -> SafetyStop? {
        previous == nil && wasHolding ? current : nil
    }
}

struct SafetyInputs: Equatable {
    // nil on a Mac without a battery.
    var batteryPercent: Int?
    var onBattery: Bool
    var thermalState: ProcessInfo.ThermalState
    /// What macOS says about the battery on power. It is kept for the
    /// record and decides nothing: a Mac at a charge limit and a full Mac
    /// both say "not charging" on a good charger. See `PowerDrain`.
    var charging = false
}

/// Says when the battery falls while the Mac is on power: a phone charger,
/// a power bank or a display port that gives less than the Mac uses. macOS
/// then still reports wall power.
///
/// Only a level that falls counts. It fell when it is 2 points or more
/// below the level at the moment the power came, or below the level it
/// last rose to. A Mac that rests at a charge limit or at full stays at
/// its level, so it never counts.
///
/// Nothing was seen during a hole between two samples (`SampleGap`): the
/// Mac can have been off the charger for all of a sleep. So the count
/// starts again at the level after the hole.
struct PowerDrain: Equatable {
    static let fallPoints = 2

    private(set) var draining = false
    /// The level the fall is counted from. Nil on battery.
    private var reference: Int?
    private var last: Int?

    /// - Parameters:
    ///   - latched: a battery stop is on. A level that rises then ends
    ///   nothing: the Mac sleeps and uses less, so the weak charger gains
    ///   a point, and the stop would go off and on.
    ///   - afterGap: there is a hole between this sample and the one
    ///   before it. A stop that is on stays: it ends as every battery stop
    ///   does, and not with each sleep of the Mac.
    mutating func update(percent: Int?, onBattery: Bool, latched: Bool, afterGap: Bool = false) {
        guard let percent, !onBattery else {
            self = PowerDrain()
            return
        }
        if afterGap, !(latched && draining) {
            restart(at: percent)
            return
        }
        defer { last = percent }
        guard let reference, let last else {
            self.reference = percent
            return
        }
        if percent > last, !(latched && draining) {
            self.reference = percent
            draining = false
        } else if reference - percent >= Self.fallPoints {
            draining = true
        }
    }

    /// The stop ended: the fall is counted from this level.
    mutating func restart(at percent: Int?) {
        self = PowerDrain()
        reference = percent
        last = percent
    }
}

// Says when keeping the Mac awake has to stop. SleepDisabled blocks the
// kernel's own low-battery and thermal sleep, so the app has to watch both.
struct SafetyMonitor {
    static let defaultBatteryFloorPercent = 20
    // A battery stop ends this many points above the floor, so a level that
    // hovers at the floor does not switch the stop on and off.
    static let batteryRecoveryPoints = 5

    var batteryFloorPercent = SafetyMonitor.defaultBatteryFloorPercent
    /// Off: the battery never stops a hold, and the Mac runs until the
    /// hardware cuts the power. Heat still stops.
    var batteryFloorEnabled = true
    private var batteryStopped = false
    private var drain = PowerDrain()

    /// The battery falls while the Mac is on power.
    var drainingOnPower: Bool { drain.draining }

    // Heat comes first: it is the one that can hurt the Mac.
    // `afterGap`: see `PowerDrain.update`.
    mutating func update(_ inputs: SafetyInputs, afterGap: Bool = false) -> SafetyStop? {
        drain.update(percent: inputs.batteryPercent, onBattery: inputs.onBattery, latched: batteryStopped, afterGap: afterGap)
        let (stop, stopped) = Self.evaluate(
            inputs, floor: batteryFloorEnabled ? batteryFloorPercent : nil, batteryStopped: batteryStopped, drainingOnPower: drain.draining
        )
        if batteryStopped, !stopped { drain.restart(at: inputs.onBattery ? nil : inputs.batteryPercent) }
        batteryStopped = stopped
        return stop
    }

    // The thermal state needs no latch of its own: macOS already moves it in
    // coarse, slow steps. A nil floor is the battery floor switched off.
    // The floor counts on battery, and on a charger that does not hold the
    // level: SleepDisabled would let that Mac run empty too.
    static func evaluate(
        _ inputs: SafetyInputs, floor: Int?, batteryStopped: Bool, drainingOnPower: Bool = false
    ) -> (stop: SafetyStop?, batteryStopped: Bool) {
        var stopped = false
        if let floor, inputs.onBattery || drainingOnPower, let percent = inputs.batteryPercent {
            stopped = batteryStopped ? percent < floor + batteryRecoveryPoints : percent <= floor
        }
        switch inputs.thermalState {
        case .serious, .critical:
            return (.tooHot, stopped)
        default:
            break
        }
        if stopped, let percent = inputs.batteryPercent {
            return (inputs.onBattery ? .batteryLow(percent: percent) : .weakCharger(percent: percent), stopped)
        }
        return (nil, stopped)
    }
}

/// What the app says about the two stops, true with the battery floor on
/// and off.
enum SafetyText {
    /// For the setup window.
    static func stillSleeps(_ settings: DetectionSettings) -> String {
        settings.batteryFloorEnabled
            ? "Your Mac still sleeps when the battery is at \(PanelText.percent(settings.batteryFloorPercent)) and when it gets too hot."
            : "Your Mac still sleeps when it gets too hot. The battery limit is off."
    }

    /// Which notifications have no switch.
    static func alwaysTold(batteryFloorEnabled: Bool) -> String {
        batteryFloorEnabled
            ? "You always get a notification when your Mac sleeps for low battery or heat"
            : "You always get a notification when your Mac sleeps for heat, and when the battery is at 10% and at 5%"
    }

    static let floorOnHelp = "Agent Caffeine lets your Mac sleep when the battery is at this level, even while an agent is working. This applies with the lid open too."
    static let floorOffWarning = "Your agents keep working until the battery is empty. Your Mac then turns off at once, and work that is not saved is lost."
    /// Below the warning: the closed lid limit is for agents alone, so
    /// with the floor off only heat ends what was asked for.
    static let floorOffLidClosed = "With this off, a command line hold or the mode Always can empty the battery with the lid closed."
    static let floorOffQuestion = "Let the battery run empty?"
    static let floorOffConsequence = "With this off, Agent Caffeine keeps your Mac awake until the battery is empty. Your Mac then turns off at once, and work that is not saved can be lost."
}

/// With the battery floor off nothing stops the hold, so the user is told
/// when the battery gets low: once at 10 percent and once at 5 percent,
/// while Agent Caffeine keeps the Mac awake on battery, or on a charger
/// that does not hold the level.
struct NoLimitBatteryWarning: Equatable {
    static let levels = [10, 5]
    /// A level is told again after the battery was above this, or charged.
    static let resetAbovePercent = 15

    private var told: Set<Int> = []

    static func notificationText(percent: Int) -> String {
        "The battery is at \(PanelText.percent(percent)). Agent Caffeine keeps your Mac awake because the battery limit is off."
    }

    /// The battery level to tell the user about, nil for none.
    mutating func update(_ inputs: SafetyInputs, drainingOnPower: Bool = false, floorEnabled: Bool, holding: Bool) -> Int? {
        guard !floorEnabled, inputs.onBattery || drainingOnPower, let percent = inputs.batteryPercent, percent <= Self.resetAbovePercent else {
            told = []
            return nil
        }
        guard holding, let level = Self.levels.last(where: { percent <= $0 }), !told.contains(level) else { return nil }
        // The level above is not told after the one below it.
        told.formUnion(Self.levels.filter { $0 >= level })
        return percent
    }
}
