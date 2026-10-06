import Foundation

enum SafetyStop: Equatable {
    case batteryLow(percent: Int)
    case tooHot
}

extension SafetyStop {
    /// The text of the notification that tells the user why the Mac slept.
    var notificationText: String {
        switch self {
        case .batteryLow(let percent): return "agent caffeine let your Mac sleep because the battery is at \(percent) percent"
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
    private var batteryStopped = false

    // Heat comes first: it is the one that can hurt the Mac.
    mutating func update(_ inputs: SafetyInputs) -> SafetyStop? {
        let (stop, stopped) = Self.evaluate(inputs, floor: batteryFloorPercent, batteryStopped: batteryStopped)
        batteryStopped = stopped
        return stop
    }

    // The thermal state needs no latch of its own: macOS already moves it in
    // coarse, slow steps.
    static func evaluate(_ inputs: SafetyInputs, floor: Int, batteryStopped: Bool) -> (stop: SafetyStop?, batteryStopped: Bool) {
        var stopped = false
        if inputs.onBattery, let percent = inputs.batteryPercent {
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
