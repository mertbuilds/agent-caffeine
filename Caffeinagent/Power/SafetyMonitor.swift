import Foundation

enum SafetyStop: Equatable {
    case batteryLow(percent: Int)
    case tooHot
}

extension SafetyStop {
    /// The text of the notification that tells the user why the Mac slept.
    var notificationText: String {
        switch self {
        case .batteryLow(let percent): return "agent caffeine let your Mac sleep because the battery is at \(PanelText.percent(percent))"
        case .tooHot: return "agent caffeine let your Mac sleep because it got too hot"
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

    // Heat comes first: it is the one that can hurt the Mac.
    mutating func update(_ inputs: SafetyInputs) -> SafetyStop? {
        let (stop, stopped) = Self.evaluate(inputs, floor: batteryFloorEnabled ? batteryFloorPercent : nil, batteryStopped: batteryStopped)
        batteryStopped = stopped
        return stop
    }

    // The thermal state needs no latch of its own: macOS already moves it in
    // coarse, slow steps. A nil floor is the battery floor switched off.
    static func evaluate(_ inputs: SafetyInputs, floor: Int?, batteryStopped: Bool) -> (stop: SafetyStop?, batteryStopped: Bool) {
        var stopped = false
        if let floor, inputs.onBattery, let percent = inputs.batteryPercent {
            stopped = batteryStopped ? percent < floor + batteryRecoveryPoints : percent <= floor
        }
        switch inputs.thermalState {
        case .serious, .critical:
            return (.tooHot, stopped)
        default:
            break
        }
        if stopped, let percent = inputs.batteryPercent {
            return (.batteryLow(percent: percent), stopped)
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
            ? "agent caffeine always tells you when it lets your Mac sleep because the battery is low or your Mac got too hot. These notifications have no switch, so you do not miss them."
            : "agent caffeine always tells you when it lets your Mac sleep because it got too hot. The battery limit is off, so it also tells you when the battery is at 10% and at 5%. These notifications have no switch, so you do not miss them."
    }

    static let floorOnHelp = "agent caffeine lets your Mac sleep when the battery is at this level, even while an agent is working. This applies with the lid open too."
    static let floorOffWarning = "Your agents keep working until the battery is empty. Your Mac then turns off at once, and work that is not saved is lost."
    static let floorOffQuestion = "Let the battery run empty?"
    static let floorOffConsequence = "With this off, agent caffeine keeps your Mac awake until the battery is empty. Your Mac then turns off at once, and work that is not saved can be lost."
}

/// With the battery floor off nothing stops the hold, so the user is told
/// when the battery gets low: once at 10 percent and once at 5 percent,
/// while agent caffeine keeps the Mac awake on battery.
struct NoLimitBatteryWarning: Equatable {
    static let levels = [10, 5]
    /// A level is told again after the battery was above this, or charged.
    static let resetAbovePercent = 15

    private var told: Set<Int> = []

    static func notificationText(percent: Int) -> String {
        "The battery is at \(PanelText.percent(percent)). agent caffeine keeps your Mac awake because the battery limit is off."
    }

    /// The battery level to tell the user about, nil for none.
    mutating func update(_ inputs: SafetyInputs, floorEnabled: Bool, holding: Bool) -> Int? {
        guard !floorEnabled, inputs.onBattery, let percent = inputs.batteryPercent, percent <= Self.resetAbovePercent else {
            told = []
            return nil
        }
        guard holding, let level = Self.levels.last(where: { percent <= $0 }), !told.contains(level) else { return nil }
        // The level above is not told after the one below it.
        told.formUnion(Self.levels.filter { $0 >= level })
        return percent
    }
}
