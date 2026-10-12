import Foundation

/// When the Mac had no way to the network for a time without a break,
/// agent sessions stop counting as a reason to keep it awake: most agents
/// cannot work without the internet. `HoldPolicy` then lets go of every
/// agent that only says it works or waits (`AgentStop.offline`).
///
/// An agent that uses a model on this Mac (Ollama, LM Studio) can work
/// offline, and is let go all the same: the model server is not a child
/// command of the agent. The way out is the choice "Never", and the
/// texts of the settings, the README and the release note say so.
///
/// What the user or a program asked for keeps holding: a hold from the
/// command line or through MCP, a job hold of "Wake for jobs", "stay
/// reachable" and the mode "always". An agent with a busy child command
/// keeps holding too (`AgentReading.runsBusyCommand`): a build or a test
/// needs no network.
///
/// Offline is what `NetworkPath.isOnline` says, read with each sample
/// (`FrameContext.offline`). No request is sent, so a Wi-Fi that is
/// connected with no internet behind it is not seen: that Mac counts as
/// online, and this rule does nothing for it.
///
/// The time is awake time with no path. A sleep counts for nothing, and
/// the count starts fresh after it: a Mac that slept offline for hours
/// does not let go at once when it wakes, and a Mac that is opened in a
/// place with no network gives its agents the whole time. One sample that
/// sees a path ends the count, and the agents count again at once.
///
/// Pure: the caller passes the path state and the time of each sample.
struct OfflineRule: Equatable {
    static let defaultMinutes = 10
    static let minuteChoices = [5, 10, 30]
    /// What the setting holds for "Never".
    static let never = 0
    /// A hidden default for the test runner: the limit in seconds, in
    /// place of the minutes of the settings. It is read at every sample.
    /// See `TestLimit` for when it counts.
    static let testSecondsKey = "OfflineLimitSecondsForTests"

    /// The hidden default, 0 while the switch of the tests is off.
    static func testSeconds(in defaults: UserDefaults) -> TimeInterval {
        TestLimit.seconds(forKey: testSecondsKey, in: defaults)
    }

    /// Nil is never.
    var limit: TimeInterval? = TimeInterval(defaultMinutes) * 60
    /// Seconds the Mac was awake with no path, without a break and since
    /// the last sleep. Nil while it has a path.
    private(set) var offlineFor: TimeInterval?
    private var last: SampleTime?

    /// Agents do not keep the Mac awake now.
    var agentsReleased: Bool {
        guard let limit, let offlineFor else { return false }
        return offlineFor >= limit
    }

    /// - Parameter offline: `FrameContext.offline` of the sample.
    mutating func update(offline: Bool, at time: SampleTime) {
        defer { last = time }
        guard offline else {
            offlineFor = nil
            return
        }
        guard let counted = offlineFor, let last else {
            offlineFor = 0
            return
        }
        let wall = time.at.timeIntervalSince(last.at)
        if let before = last.awake, let after = time.awake, after >= before {
            let awake = after - before
            // The date moved without the Mac being awake for it: a sleep.
            // Awake time between two late samples counts in full.
            offlineFor = wall - awake > SampleGap.clockTolerance ? 0 : counted + awake
        } else {
            // Without the awake clock a hole is taken for a sleep.
            offlineFor = wall > SampleGap.threshold ? 0 : counted + max(0, wall)
        }
    }
}

extension DetectionSettings {
    /// The limit of the settings, nil for "Never". `testSeconds` is the
    /// hidden default (`OfflineRule.testSeconds`), see `TestLimit`.
    func offlineLimit(testSeconds: TimeInterval = 0) -> TimeInterval? {
        let minutes = offlineLimitMinutes == OfflineRule.never ? nil : TimeInterval(offlineLimitMinutes) * 60
        return TestLimit.shortened(minutes, to: testSeconds)
    }
}
