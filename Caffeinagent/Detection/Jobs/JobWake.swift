import Foundation

/// What "Wake for jobs" is told at every turn.
struct JobWakeInput: Equatable {
    /// What `JobStore` read, with every job switched off.
    var readings: [JobSourceReading] = []
    var settings = JobSettings()
    /// `macAwake`, `wakesInLastDay` and `alarmSet` are filled in by `JobWake`.
    var context = JobPlanContext()
    /// The app runs from the Applications folder. The helper takes calls
    /// from that copy only.
    var inApplications = true
    /// The helper is allowed in Login Items.
    var helperEnabled = true
}

/// The one thing Settings says about the state of "Wake for jobs".
enum JobWakeStatus: Equatable {
    /// The switch of the feature is off.
    case off
    case needsApplications
    /// The helper is not set up.
    case needsHelper
    /// The helper gave no answer, or it is of a build without alarms.
    case helperSilent
    case noAlarm(NoAlarmReason)
    /// The helper was asked and has not answered yet.
    case asking
    case alarmSet(JobAlarm)
    case refused(WakeAlarmRefusal)
}

/// The rules of the loop of "Wake for jobs": which time goes to the
/// helper and when, what its answer means, when a job hold opens and
/// ends, the alarms of the last day, and the history. Pure: the caller
/// passes the times and makes the calls.
///
/// - The planner is asked at every turn, so a change of a job, a setting,
///   the power source, the battery, a stop, a pause or the license moves
///   the alarm at once.
/// - A new time goes to the helper at once. The same time goes again
///   every `renewEvery` seconds the Mac was awake: the helper takes an
///   alarm away that nobody asked for in 10 minutes.
/// - 0 goes when no alarm is wanted and one can still be set.
/// - After macOS said the Mac goes to sleep, the plan is made for a Mac
///   that sleeps, until the Mac woke in full.
/// - When the time of an alarm that is set has come, a job hold opens.
struct JobWake: Equatable {
    /// Well inside `WakeAlarmLimits.lease`.
    static let renewEvery: TimeInterval = 180
    /// A time the helper did not take is sent again after this long.
    static let retryAfter: TimeInterval = 60
    /// After "too often" the helper takes no new time for a while.
    static let retryAfterTooOften: TimeInterval = 600
    /// The app ran again this long after the alarm: it is not what woke
    /// the Mac, or the Mac slept again before the app got its turn.
    static let lateAfter: TimeInterval = 120
    /// The helper sets whole seconds.
    private static let sameTime: TimeInterval = 0.5

    private(set) var memory: JobWakeMemory
    private(set) var plan = JobPlan(alarm: nil, noAlarm: .featureOff, nextRuns: [])
    private(set) var status = JobWakeStatus.off
    /// The job holds that are open, the oldest first.
    private(set) var holds: [JobHold] = []
    /// The alarm the helper confirmed, nil for none.
    private(set) var alarm: JobAlarm?

    private var settings = JobSettings()
    private var usable = false
    private var inApplications = true
    /// The time that is with the helper and not answered, 0 for a cancel.
    private var askedTime: TimeInterval?
    private var asked: JobAlarm?
    /// When the helper last confirmed an alarm, in awake seconds.
    private var confirmedAwake: TimeInterval?
    private var failedTime: TimeInterval?
    private var refusal: WakeAlarmRefusal?
    private var retryAt: TimeInterval = 0
    /// The refused time after which 0 went to the helper, so the alarm
    /// it kept goes. Nil when the time is tried again.
    private var clearedFor: TimeInterval?
    /// The 0 that is with the helper went for that reason.
    private var clearing = false
    private var silent = false
    /// macOS said the Mac goes to sleep, and it did not wake in full since.
    private var sleepAnnounced = false
    private var asleepSeen: TimeInterval?

    init(memory: JobWakeMemory = JobWakeMemory()) {
        self.memory = memory
    }

    /// The alarms that count for the limit of a day.
    var wakesInLastDay: Int { memory.ledger.count }
    /// The holds whose job the caller looks for among the processes.
    var watched: [JobHold] { holds.filter(\.isWatched) }
    /// When the caller has to come back at the latest: the time of the
    /// alarm, and the end of each hold.
    var nextTurn: Date? {
        ([alarm?.at] + holds.map { Optional($0.endsAt) }).compactMap { $0 }.min()
    }
    /// True when 0 has to go to the helper before the app quits.
    var owesCancel: Bool { alarm != nil || memory.owedAlarm != nil || (askedTime ?? 0) > 0 }

    // MARK: Turn

    /// One turn of the loop.
    /// - Parameters:
    ///   - awake: seconds the Mac was awake (`SampleGap.awakeSeconds`).
    ///   - asleep: seconds the Mac slept (`SampleGap.asleepSeconds`).
    ///   - willSleep: macOS says the Mac goes to sleep now.
    /// - Returns: the time to send to the helper now, 0 for a cancel, nil
    ///   for no call. The answer goes to `answered`.
    mutating func turn(
        _ input: JobWakeInput, now: Date, awake: TimeInterval, asleep: TimeInterval, clock: JobClock, willSleep: Bool = false
    ) -> TimeInterval? {
        let slept = asleepSeen.map { asleep - $0 > SampleGap.clockTolerance } ?? false
        asleepSeen = asleep
        if willSleep { sleepAnnounced = true }
        settings = input.settings
        inApplications = input.inApplications
        usable = input.inApplications && input.helperEnabled
        let jobs = input.settings.applied(to: input.readings.flatMap(\.jobs))

        ring(jobs: jobs, slept: slept, now: now)
        memory.prune(now: now)
        settleHolds(now: now)

        var context = input.context
        context.macAwake = !sleepAnnounced
        context.wakesInLastDay = wakesInLastDay
        context.alarmSet = alarm
        plan = JobPlanner.plan(jobs: jobs, settings: input.settings, context: context, now: now, clock: clock)
        defer { status = currentStatus }

        guard input.helperEnabled else {
            // A helper that is not allowed runs no more, and its alarm
            // went with it.
            alarm = nil
            memory.owedAlarm = nil
            askedTime = nil
            return nil
        }
        // The plan for a Mac that goes to sleep does not wait for an
        // answer: the helper takes the calls in their order.
        guard input.inApplications, askedTime == nil || willSleep else { return nil }
        let wanted = plan.alarm
        let time = wanted.map { $0.at.timeIntervalSince1970.rounded() } ?? 0
        if time > 0 {
            if let alarm, isSame(alarm.at.timeIntervalSince1970, time) {
                guard awake - (confirmedAwake ?? -.infinity) >= Self.renewEvery || willSleep else { return nil }
                // The helper refuses a time that is this close, also the
                // one it has. The lease is longer than that.
                guard time - now.timeIntervalSince1970 >= JobSettings.minimumAhead else { return nil }
            } else if failedTime == time, awake < retryAt {
                // The helper refused the new time and kept the alarm it
                // had. That alarm is not wanted any more, and it can be
                // for a job that is off: it goes, once for each try of
                // the new time.
                guard refusal != nil, clearedFor != time, alarm != nil || memory.owedAlarm != nil else { return nil }
                clearedFor = time
                clearing = true
                askedTime = 0
                asked = nil
                return 0
            }
        } else {
            guard owesCancel else { return nil }
            if failedTime == 0, awake < retryAt { return nil }
        }
        clearing = false
        askedTime = time
        asked = wanted
        return time
    }

    /// The Mac woke in full: the plan is for a Mac that is awake again.
    mutating func wokeInFull() {
        sleepAnnounced = false
    }

    /// The time of the alarm has come: the Mac woke for it, or was awake.
    private mutating func ring(jobs: [ScheduledJob], slept: Bool, now: Date) {
        guard let rung = alarm, now >= rung.at else { return }
        alarm = nil
        memory.owedAlarm = nil
        let at = rung.at.timeIntervalSince1970
        let kind: JobEvent.Kind
        if !slept {
            kind = .alarmWhileAwake
        } else {
            // The Mac may have woken and slept again, so it counts.
            memory.ledger.append(at)
            kind = now.timeIntervalSince(rung.at) > Self.lateAfter ? .alarmSeenLate : .wokeAtAlarm
        }
        memory.history.note(kind, at: now, alarmAt: at, job: rung.jobName)
        guard settings.wakeForJobs, let job = jobs.first(where: { $0.id == rung.jobID }),
              let hold = JobHold.open(job: job, fireAt: rung.fireAt, settings: settings), hold.isTimely(now: now),
              !holds.contains(where: { $0.id == hold.id }) else { return }
        holds.append(hold)
    }

    // MARK: The helper's answer

    /// What the helper said to the time that `turn` gave. An answer to
    /// another time than the last one is late and means nothing.
    mutating func answered(_ result: WakeAlarmResult, for time: TimeInterval, now: Date, awake: TimeInterval) {
        guard askedTime == time else { return }
        let wanted = asked
        let clearing = clearing
        self.clearing = false
        askedTime = nil
        asked = nil
        defer { status = currentStatus }
        switch result {
        case .set(let at):
            silent = false
            failedTime = nil
            refusal = nil
            clearedFor = nil
            confirmedAwake = awake
            memory.owedAlarm = at
            guard var next = wanted else { return }
            next.at = Date(timeIntervalSince1970: at)
            if alarm.map({ !isSame($0.at.timeIntervalSince1970, at) }) ?? true {
                memory.history.note(.alarmSet, at: now, alarmAt: at, job: next.jobName)
            }
            alarm = next
        case .cancelled:
            silent = false
            // After a cancel that followed a refused time, the refusal
            // of that time is still what is known.
            if !clearing {
                failedTime = nil
                refusal = nil
            }
            if let at = alarm?.at.timeIntervalSince1970 ?? memory.owedAlarm {
                memory.history.note(.alarmCancelled, at: now, alarmAt: at, job: alarm?.jobName)
            }
            alarm = nil
            memory.owedAlarm = nil
        case .refused(let reason):
            // A refusal changes nothing in the helper: an alarm that is
            // set stays.
            silent = false
            // The cancel after a refused time failed too. The refusal of
            // the time and its retry stay as they are, and the cancel is
            // tried again with the time.
            if clearing { return }
            if time > 0 { clearedFor = nil }
            if failedTime != time || refusal != reason {
                memory.history.note(.alarmRefused, at: now, alarmAt: time > 0 ? time : nil, job: wanted?.jobName, reason: reason.rawValue)
            }
            failedTime = time
            refusal = reason
            retryAt = awake + (reason == .tooOften ? Self.retryAfterTooOften : Self.retryAfter)
        case .helperNotAvailable:
            if !silent { memory.history.note(.helperSilent, at: now) }
            silent = true
            failedTime = time
            refusal = nil
            retryAt = awake + Self.retryAfter
            // The helper takes an alarm away that nobody asked for in
            // the time of the lease, and a helper that stopped took it
            // away at once.
            if awake - (confirmedAwake ?? -.infinity) >= WakeAlarmLimits.lease {
                alarm = nil
                memory.owedAlarm = nil
            }
        }
    }

    /// The helper was stopped and started again, as after an update of
    /// the app. Its alarm went with it, and the next turn sets it again.
    mutating func helperReplaced() {
        alarm = nil
        memory.owedAlarm = nil
        failedTime = nil
        refusal = nil
        clearedFor = nil
        retryAt = 0
        silent = false
        status = currentStatus
    }

    /// The app quits or the helper is removed, and 0 went to the helper.
    mutating func cancelled(_ result: WakeAlarmResult, now: Date) {
        if result == .cancelled, let at = alarm?.at.timeIntervalSince1970 ?? memory.owedAlarm {
            memory.history.note(.alarmCancelled, at: now, alarmAt: at, job: alarm?.jobName)
        }
        // When the call got lost, the lease of the helper ends the alarm.
        alarm = nil
        memory.owedAlarm = nil
        askedTime = nil
        asked = nil
        status = currentStatus
    }

    // MARK: Holds

    /// What the caller saw of the jobs of the watched holds, by the id of
    /// the hold. A hold with no entry could not be looked for: its start
    /// grace and its cap decide.
    mutating func observe(_ running: [String: Bool], now: Date) {
        for index in holds.indices {
            guard let runs = running[holds[index].id] else { continue }
            let seen = holds[index].seenAt != nil
            holds[index].observe(running: runs, now: now)
            if !seen, holds[index].seenAt != nil { memory.history.note(.jobSeen, at: now, job: holds[index].name) }
        }
        settleHolds(now: now)
    }

    /// "Stop" on the line of a job hold. The job itself runs on.
    mutating func stop(holdID: String, now: Date) {
        guard let index = holds.firstIndex(where: { $0.id == holdID }) else { return }
        memory.history.note(.endedByStop, at: now, job: holds[index].name)
        holds.remove(at: index)
    }

    /// Takes away the holds that are over, with a line in the history.
    ///
    /// Nothing puts the Mac to sleep here. When a hold ends, Agent
    /// Caffeine lets go, and the Mac sleeps by its own timers, or at once
    /// with the lid closed on battery. A sleep request after the job
    /// ("sleep back", note D7 item 8) is not in this version: it needs
    /// the proof that Agent Caffeine caused the wake and that nobody
    /// uses the Mac, and that is not measured yet.
    private mutating func settleHolds(now: Date) {
        holds.removeAll { hold in
            let kind: JobEvent.Kind?
            if !settings.wakeForJobs || !settings.isOn(hold.jobID) {
                kind = .endedByStop
            } else {
                switch hold.state(now: now) {
                case .waiting, .running: return false
                case .ended: kind = .jobEnded
                case .neverStarted: kind = .endedByGrace
                case .cutAtCap: kind = .endedByCap
                case .bridgeOver: kind = .bridgeOver
                // The clock was set back to before the alarm.
                case .notOpen: kind = nil
                }
            }
            if let kind { memory.history.note(kind, at: now, job: hold.name) }
            return true
        }
    }

    // MARK: Status

    private var currentStatus: JobWakeStatus {
        guard settings.wakeForJobs else { return .off }
        guard inApplications else { return .needsApplications }
        guard usable else { return .needsHelper }
        if silent { return .helperSilent }
        if let reason = plan.noAlarm { return .noAlarm(reason) }
        guard let wanted = plan.alarm else { return .noAlarm(.noRunKnown) }
        let time = wanted.at.timeIntervalSince1970.rounded()
        if let alarm, isSame(alarm.at.timeIntervalSince1970, time) { return .alarmSet(alarm) }
        if failedTime == time, let refusal { return .refused(refusal) }
        return .asking
    }

    private func isSame(_ first: TimeInterval, _ second: TimeInterval) -> Bool {
        abs(first - second) <= Self.sameTime
    }
}
