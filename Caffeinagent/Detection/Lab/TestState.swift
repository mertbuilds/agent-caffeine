import Foundation

/// What the running app decided and what it believes of the Mac, as one
/// file for the test runner in `scripts/actest`. The lab recorder runs an
/// engine of its own, so only this file says what the real app does.
///
/// Privacy: the file holds times, numbers, flags, and names that come
/// from a fixed list in the code. The only texts from outside are the
/// path of the bundle and the id of a hold from the command line, which
/// is letters and digits. No name of a session, no title, no folder, no
/// project, no terminal, no reason of a hold, no name of a job, no name
/// of a Wi-Fi network, no password and no text of a notification has a
/// field here. Add no field of type String
/// that takes its value from anything but an enum of the app.
struct TestState: Codable, Equatable {
    static let currentVersion = 1
    /// The hidden switch: `defaults write com.caffeinagent.app
    /// StateForTests -bool true`. Off, the file is not written.
    static let defaultsKey = HoldStore.stateSwitchKey
    /// What stands for the id of an agent the user added by name.
    static let userAgentID = "user"

    struct App: Codable, Equatable {
        var version: String
        var build: String
        var path: String
        var pid: Int32
    }

    struct Decision: Codable, Equatable {
        var hold: Bool
        /// The case of `HoldHeadline`: "working", "noAgents", "paused".
        var headline: String
        /// The kind of the safety stop, where the headline is one, and
        /// the rule that let go of the agents, where it is that: "offline",
        /// "closedLidTime" or "closedLidDrop".
        var reason: String?
        var stop: Bool
        /// The app holds its power assertions.
        var assertion: Bool
    }

    struct Flag: Codable, Equatable {
        /// The decision wants `SleepDisabled`.
        var wanted: Bool
        /// `HelperStatus`.
        var helper: String
        /// `HelperSetup`.
        var setup: String
        /// The flag as the app believes it is.
        var set: Bool
    }

    struct Power: Codable, Equatable {
        /// "battery" or "ac".
        var source: String
        var percent: Int?
        var charging: Bool
    }

    struct Lid: Codable, Equatable {
        var closed: Bool
        /// Degrees. Nil on a Mac without the sensor.
        var angle: Double?
    }

    /// One closed-lid period: a hold with the lid closed on battery, until
    /// the lid opens or power comes. See `ClosedLidLimit`.
    struct ClosedLid: Codable, Equatable {
        var since: TimeInterval
        /// Seconds the app kept the Mac awake in this period.
        var heldSeconds: TimeInterval
        var percentAtStart: Int?
        /// The limits in use. Nil is no limit.
        var limitSeconds: TimeInterval?
        var limitDrop: Int?
        /// "closedLidTime" or "closedLidDrop", nil while the limit is
        /// not reached.
        var stop: String?
        /// The limit is reached: agents do not keep the Mac awake.
        var agentsReleased: Bool
    }

    /// The way to the network and the offline rule. See `OfflineRule`.
    struct Network: Codable, Equatable {
        var online: Bool
        /// Seconds awake with no path, without a break. Nil while online.
        var offlineSeconds: TimeInterval?
        /// The limit in use. Nil is never.
        var limitSeconds: TimeInterval?
        /// The rule is on: agents do not keep the Mac awake.
        var agentsReleased: Bool
    }

    struct Agent: Codable, Equatable {
        /// An id of the catalog, or `userAgentID`.
        var id: String
        var pid: Int32
        var role: String?
        var state: String
        /// `VerdictReason.code`.
        var why: String
        var level: String
        /// `HoldCause.code`, nil when the instance does not hold.
        var hold: String?
    }

    struct Hold: Codable, Equatable {
        var id: String
        var kind: String
        var start: TimeInterval
        var end: TimeInterval
    }

    struct Alarm: Codable, Equatable {
        var at: TimeInterval
        var fireAt: TimeInterval
        /// `ScheduledJob.Source`, nil when the job is not in the list.
        var source: String?
    }

    struct JobHoldRow: Codable, Equatable {
        var source: String
        var start: TimeInterval
        var fireAt: TimeInterval
        var end: TimeInterval
    }

    /// Something that happened, by its kind and its time alone.
    struct Event: Codable, Equatable {
        var kind: String
        var at: TimeInterval
    }

    struct Jobs: Codable, Equatable {
        /// The switch of "Wake for jobs".
        var on: Bool
        /// The case of `JobWakeStatus`.
        var status: String
        /// How many jobs were found, and how many of them the user
        /// switched on.
        var found: Int
        var enabled: Int
        var alarm: Alarm?
        var holds: [JobHoldRow]
        /// The newest first.
        var history: [Event]
    }

    /// "Join your iPhone hotspot". The name of the hotspot and its
    /// password have no field here, and no other network name has one.
    struct Hotspot: Codable, Equatable {
        /// The switch of the feature.
        var on: Bool
        /// A name and a password are saved.
        var configured: Bool
        /// `HotspotHop.State.code`: "idle", "waiting", "scanning",
        /// "joined", "notFound", "hoppedBack", or "failed:" and a
        /// `HopFailure`.
        var state: String
        /// When the last try ended. Nil while none did.
        var since: TimeInterval?
    }

    var v = TestState.currentVersion
    /// Seconds since the epoch, as every time here.
    var at: TimeInterval
    var app: App
    /// The switch of Agent Caffeine.
    var on: Bool
    var pausedUntil: TimeInterval?
    var reachableUntil: TimeInterval?
    /// `AwakeMode.rawValue`.
    var mode: String
    /// "licensed", "trial" or "expired".
    var entitlement: String
    var trialDaysLeft: Int?
    var decision: Decision
    var flag: Flag
    /// Nil until the first sample.
    var power: Power?
    var lid: Lid?
    /// The kind of the safety stop, nil when there is none.
    var safety: String?
    /// Nil while there is no closed-lid period.
    var closedLid: ClosedLid?
    /// Nil until the first sample.
    var network: Network?
    /// `WakeGate.code`.
    var gate: String
    var agents: [Agent]
    var holds: [Hold]
    var jobs: Jobs
    var hotspot = Hotspot(on: false, configured: false, state: "idle")
    /// The last notifications that were sent, the newest first.
    var notices: [Event]
    /// When the lid chime played last.
    var chimeAt: TimeInterval?

    /// One line, the keys in order.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(self)
    }
}

/// The notifications the app sends, for `TestState.notices`.
enum TestNoticeKind: String, CaseIterable {
    case waiting
    case finished
    case safetyStop
    case batteryWarning
    case trial
    case hidden
    /// The offline rule ended a hold.
    case offline
    /// The closed lid limit ended a hold.
    case closedLidLimit
}
