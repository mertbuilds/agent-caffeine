import Foundation

// Shared by the app and the root helper. The helper takes two booleans and
// one wake time from its client and nothing else: no strings, no paths, no
// commands and no event types.
@objc protocol SleepFlagHelperProtocol {
    // Replies with the value read back from the kernel.
    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void)
    func status(reply: @escaping (_ sleepDisabled: Bool, _ setByHelper: Bool, _ version: String) -> Void)
    // Replies with the current value, so the app sees a flag the helper
    // cleared on its own.
    func heartbeat(reply: @escaping (Bool) -> Void)
    // After an update of the app: the helper clears a flag it owns, replies
    // and exits. launchd starts the binary that is in the bundle now on the
    // next connection, and nothing about the registration changes.
    func retire(reply: @escaping () -> Void)
    // One wake alarm for the whole Mac. `time` is seconds since 1970, and 0
    // takes the alarm away. The helper fixes the rest itself: the kind of
    // event (a wake, never a power on) and the name the event is listed
    // under. The app sends the time again every few minutes: the helper
    // takes away an alarm that nobody asked for in 10 minutes of awake time.
    // Replies with the time that is set now, or 0, and a code: 0 for done,
    // else the raw value of a WakeAlarmRefusal.
    func setWakeAlarm(at time: Double, reply: @escaping (_ time: Double, _ code: Int) -> Void)
}

/// Why the helper did not set or take away the wake alarm.
enum WakeAlarmRefusal: Int, Equatable {
    /// Not a number that is a time.
    case notATime = 1
    /// Less than `WakeAlarmLimits.minimumLead` ahead, or in the past.
    case tooSoon = 2
    /// More than `WakeAlarmLimits.maximumLead` ahead.
    case tooFar = 3
    /// More than `WakeAlarmLimits.setsPerHour` new times in one hour.
    case tooOften = 4
    /// macOS did not take the event.
    case notScheduled = 5
    /// macOS took the event, and the list of events does not show it once.
    /// The helper took it away again.
    case notConfirmed = 6
    /// An alarm of the helper is still in the list after the cancel.
    case notCancelled = 7
    /// A code this build does not know.
    case unknown = -1
}

enum WakeAlarmLimits {
    static let minimumLead: TimeInterval = 20
    static let maximumLead: TimeInterval = 8 * 24 * 3600
    static let setsPerHour = 30
    /// The alarm goes when the app did not ask for it again for this long,
    /// in time the Mac was awake.
    static let lease: TimeInterval = 600
    /// The alarm goes this long after the last connection of the app to
    /// the helper ended, in time the Mac was awake: the app quit with no
    /// cancel, or died. A new connection in that time keeps the alarm, as
    /// when the app starts again after an update.
    static let clientGrace: TimeInterval = 30
}

/// What a call of `setWakeAlarm` came to.
enum WakeAlarmResult: Equatable {
    /// The alarm is in the list of macOS once, at this time.
    case set(TimeInterval)
    case cancelled
    case refused(WakeAlarmRefusal)
    /// The helper is not set up, gave no answer, or is of a build that does
    /// not know the call. Never sent by the helper.
    case helperNotAvailable

    init(time: Double, code: Int) {
        if code != 0 {
            self = .refused(WakeAlarmRefusal(rawValue: code) ?? .unknown)
        } else if time > 0 {
            self = .set(time)
        } else {
            self = .cancelled
        }
    }

    /// The two numbers of the reply.
    var reply: (time: Double, code: Int) {
        switch self {
        case .set(let time): return (time, 0)
        case .cancelled: return (0, 0)
        case .refused(let reason): return (0, reason.rawValue)
        case .helperNotAvailable: return (0, WakeAlarmRefusal.unknown.rawValue)
        }
    }
}

enum SleepFlagHelper {
    static let appBundleID = "com.caffeinagent.app"
    static let label = "com.caffeinagent.app.helper"
    static let machServiceName = label
    static let plistName = "\(label).plist"
    static let teamID = "3HGP3W3TLD"
    static let heartbeatInterval: TimeInterval = 15
    static let heartbeatTimeout: TimeInterval = 60

    // Developer ID signed by this team with the given identifier. An ad hoc
    // Debug build never satisfies it.
    static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
