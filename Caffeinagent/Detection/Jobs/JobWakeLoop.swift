import Foundation
import os

/// How the loop reaches the wake alarm of the helper. The app passes the
/// controller of the helper, and a test passes a fake: no test sets a
/// real alarm.
@MainActor
protocol WakeAlarmSending: AnyObject {
    /// Seconds since 1970, 0 for no alarm.
    func wakeAlarm(at time: TimeInterval) async -> WakeAlarmResult
    /// The same where nothing can await: when the Mac goes to sleep and
    /// when the app quits. It blocks for `timeout` seconds at most.
    func wakeAlarmNow(at time: TimeInterval, timeout: TimeInterval) -> WakeAlarmResult
}

/// Looks for the jobs of the watched holds among the processes.
protocol JobRunProbing {
    /// By the id of the hold: true while the job runs. A hold with no
    /// entry could not be looked for.
    func running(_ holds: [JobHold]) async -> [String: Bool]
}

/// What Settings and the menu show of "Wake for jobs".
struct JobWakeView: Equatable {
    var status = JobWakeStatus.off
    /// Every job that was found, the next to run first.
    var runs: [JobRun] = []
    /// Per source, how the reading went.
    var sources: [ScheduledJob.Source: JobSourceStatus] = [:]
    /// The alarm that is set.
    var alarm: JobAlarm?
    /// The newest first.
    var history: [JobEvent] = []
    /// The short names of the jobs whose switch went off by itself.
    var lostSwitches: [String] = []
}

/// Runs `JobWake`: asks it at every change and every sample, makes the
/// calls to the helper it wants, feeds the job holds from the processes,
/// and saves its memory. It has no timer of its own: the owner calls
/// `run` with every sample and at `nextTurn`.
@MainActor
final class JobWakeLoop: ObservableObject {
    /// How long the Mac waits for the helper when it goes to sleep and
    /// when the app quits.
    static let blockingTimeout: TimeInterval = 2
    /// The processes are looked at no more often.
    static let probeEvery: TimeInterval = 4
    /// One `run` brings no more calls to the helper than this: its own,
    /// and those of the turns that follow an answer. `JobWake` waits
    /// before it sends a time again. This holds when a rule there is
    /// wrong too: the helper is root and is never called in a loop.
    static let callsPerRun = 3

    @PublishedOnChange private(set) var view = JobWakeView()
    /// The job holds that are open. `HoldPolicy` decides what they are worth.
    @PublishedOnChange private(set) var holds: [JobHold] = []
    /// The owner sets its timer again.
    var onChange: (() -> Void)?

    private(set) var input = JobWakeInput()

    private var core: JobWake
    private var saved: JobWakeMemory
    private let sender: WakeAlarmSending
    private let probe: JobRunProbing?
    private let defaults: UserDefaults
    private let clocks: AwakeClock
    private let now: () -> Date
    private let jobClock: () -> JobClock
    private var probing = false
    private var probedAwake = -TimeInterval.infinity
    /// The calls the `run` that came last may still make.
    private var callsLeft = JobWakeLoop.callsPerRun
    /// The call to the helper and the look at the processes that are
    /// under way. A test waits for them.
    private(set) var sending: Task<Void, Never>?
    private(set) var looking: Task<Void, Never>?
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "JobWake")

    init(
        sender: WakeAlarmSending, probe: JobRunProbing?, defaults: UserDefaults, clocks: AwakeClock = .system,
        now: @escaping () -> Date = Date.init, jobClock: @escaping () -> JobClock = { JobClock(timeZone: .current) }
    ) {
        self.sender = sender
        self.probe = probe
        self.defaults = defaults
        self.clocks = clocks
        self.now = now
        self.jobClock = jobClock
        saved = JobWakeMemoryStore.load(from: defaults)
        core = JobWake(memory: saved)
    }

    /// When `run` has to be called at the latest.
    var nextTurn: Date? { core.nextTurn }

    /// One turn. Called on every change of the input, with every sample,
    /// and at `nextTurn`.
    /// - Parameter next: what the app knows now. Nil keeps the input.
    func run(_ next: JobWakeInput? = nil) {
        if let next { input = next }
        callsLeft = Self.callsPerRun
        turn(willSleep: false)
        look()
    }

    /// macOS says the Mac goes to sleep: the alarm for a Mac that sleeps
    /// is with the helper before this returns, or the wait ran out.
    func willSleep(_ next: JobWakeInput? = nil) {
        if let next { input = next }
        turn(willSleep: true)
    }

    /// - Parameter next: what the app knows now. Nil keeps the input.
    func wokeInFull(_ next: JobWakeInput? = nil) {
        core.wokeInFull()
        run(next)
    }

    /// "Stop" on the line of a job hold.
    func stopHold(id: String) {
        core.stop(holdID: id, now: now())
        publish()
    }

    /// A new reading of the jobs. The switch of a line that cannot be
    /// told apart is forgotten, so it never comes back on another
    /// command. A switch that was on does not go in silence: the history
    /// and Settings say it.
    /// - Returns: the settings to keep.
    func forgetSwitches(ofUnclear jobs: [ScheduledJob], in settings: JobSettings) -> JobSettings {
        let lost = settings.switchesLost(toUnclear: jobs)
        if !lost.isEmpty {
            core.switchesLost(lost.map(\.name), now: now())
            publish()
        }
        return settings.withoutSwitches(ofUnclear: jobs)
    }

    /// The user closed the line about such a switch, or changed a switch.
    func closeSwitchNotice() {
        core.closeSwitchNotice()
        publish()
    }

    /// The helper was stopped and started again.
    func helperReplaced() {
        core.helperReplaced()
        run()
    }

    /// The app quits, or the helper is removed: no alarm stays behind.
    func cancelNow() {
        guard core.owesCancel else { return }
        log.info("wake alarm: cancel")
        let result = sender.wakeAlarmNow(at: 0, timeout: Self.blockingTimeout)
        core.cancelled(result, now: now())
        publish()
    }

    private func turn(willSleep: Bool) {
        // `JobWake` is not asked either: it would wait for an answer to
        // a time that was never sent. The next `run` asks it.
        guard willSleep || callsLeft > 0 else { return }
        let time = core.turn(input, now: now(), awake: clocks.awake(), asleep: clocks.asleep(), clock: jobClock(), willSleep: willSleep)
        publish()
        guard let time else { return }
        // Times only: the name of the job is not logged.
        log.info("wake alarm: asking for \(Int(time), privacy: .public)\(willSleep ? " before sleep" : "", privacy: .public)")
        if willSleep {
            answered(sender.wakeAlarmNow(at: time, timeout: Self.blockingTimeout), for: time)
            return
        }
        callsLeft -= 1
        sending = Task { [weak self, sender] in
            let result = await sender.wakeAlarm(at: time)
            self?.answered(result, for: time)
            // What changed while the call was under way.
            self?.turn(willSleep: false)
        }
    }

    private func answered(_ result: WakeAlarmResult, for time: TimeInterval) {
        log.info("wake alarm: \(Self.logText(result), privacy: .public)")
        core.answered(result, for: time, now: now(), awake: clocks.awake())
        publish()
    }

    /// Feeds the watched holds from the processes, off the main thread.
    private func look() {
        let watched = core.watched
        let awake = clocks.awake()
        guard let probe, !watched.isEmpty, !probing, awake - probedAwake >= Self.probeEvery else { return }
        probing = true
        probedAwake = awake
        looking = Task { [weak self] in
            let running = await probe.running(watched)
            guard let self else { return }
            self.probing = false
            self.core.observe(running, now: self.now())
            self.publish()
        }
    }

    private func publish() {
        if core.memory != saved {
            saved = core.memory
            JobWakeMemoryStore.save(saved, to: defaults)
        }
        var sources: [ScheduledJob.Source: JobSourceStatus] = [:]
        for reading in input.readings { sources[reading.source] = reading.status }
        let next = JobWakeView(
            status: core.status, runs: core.plan.nextRuns, sources: sources, alarm: core.alarm,
            history: core.memory.history.events.reversed(), lostSwitches: core.lostSwitches
        )
        let changed = view != next || holds != core.holds
        if view != next { view = next }
        if holds != core.holds { holds = core.holds }
        if changed { onChange?() }
    }

    static func logText(_ result: WakeAlarmResult) -> String {
        switch result {
        case .set(let time): return "set for \(Int(time))"
        case .cancelled: return "none is set"
        case .refused(let reason): return "refused, code \(reason.rawValue)"
        case .helperNotAvailable: return "the helper gave no answer"
        }
    }
}
