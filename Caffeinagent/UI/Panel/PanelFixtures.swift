#if DEBUG
import Foundation

/// The states the previews and the offscreen pictures show.
enum PanelFixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    struct Agent {
        var id: String
        var name: String
        var state: WorkState = .idle
        var reason: VerdictReason = .atPrompt
        var minutes: Double = 0
        var label: String?
        var cause: HoldCause?
        var hint: SessionHint?
    }

    static func input(_ headline: HoldHeadline, _ agents: [Agent] = []) -> PanelInput {
        var labels: [ProcessIdentity: String] = [:]
        var hints: [ProcessIdentity: SessionHint] = [:]
        var holds: [AgentHold] = []
        for (index, agent) in agents.enumerated() {
            let identity = ProcessIdentity(pid: Int32(100 + index), startTime: 0)
            labels[identity] = agent.label
            hints[identity] = agent.hint
            holds.append(AgentHold(
                reading: AgentReading(
                    agentID: agent.id, displayName: agent.name, level: .state, identity: identity,
                    verdict: AgentVerdict(state: agent.state, confidence: .reported, reason: agent.reason)
                ),
                cause: agent.cause
            ))
        }
        var clock = StateClock()
        for minutes in Set(agents.map(\.minutes)).sorted(by: >) {
            let seen = zip(agents, holds).filter { $0.0.minutes >= minutes }.map(\.1.reading)
            clock = clock.updated(with: seen, now: now.addingTimeInterval(-minutes * 60))
        }
        var decision = HoldDecision(hold: headline.keepsAwake, lidClosedFlag: false, headline: headline, perAgent: holds)
        if case .waitingHeld = headline, let waited = agents.filter({ $0.cause == .waitingForUser }).map(\.minutes).min() {
            decision.waitingEnds = now.addingTimeInterval(DetectionSettings().waitingHold - waited * 60)
        }
        var input = PanelInput(decision: decision)
        input.labels = labels
        input.hints = hints
        input.clock = clock
        return input
    }

    static func state(_ input: PanelInput) -> PanelState {
        MenuModel.state(input, now: now)
    }

    private static let idleClaude = (1...8).map { Agent(id: "claude", name: "Claude Code", minutes: Double($0) * 40) }
    private static let manyIdle = idleClaude + [
        Agent(id: "codex", name: "Codex", minutes: 395),
        Agent(id: "opencode", name: "opencode", minutes: 20),
        Agent(id: "cursor-agent", name: "Cursor Agent", minutes: 50),
        Agent(id: "gemini", name: "Gemini CLI", minutes: 90),
        Agent(id: "amp", name: "Amp", minutes: 200),
        Agent(id: "goose", name: "Goose", minutes: 3000),
        Agent(id: "aider", name: "Aider", minutes: 4000),
        Agent(id: "user:mytool", name: "mytool", reason: .ignoredByRule, minutes: 10),
    ]

    static let working = state(input(.working(.many(2)), [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 12, label: "wiki", cause: .working),
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .runningCommand(3), minutes: 3, label: "site", cause: .working),
    ] + manyIdle))

    static let waiting = state(input(.waitingHeld(.one("Codex")), [
        Agent(id: "codex", name: "Codex", state: .waitingForUser, reason: .asksPermission, minutes: 1.2, label: "caffeinagent", cause: .waitingForUser),
        Agent(id: "claude", name: "Claude Code", minutes: 25),
        Agent(id: "opencode", name: "opencode", minutes: 395),
    ]))

    static let allIdle = state(input(.idle(.many(3)), [
        Agent(id: "claude", name: "Claude Code", minutes: 25),
        Agent(id: "codex", name: "Codex", minutes: 395),
        Agent(id: "gemini", name: "Gemini CLI", minutes: 0.2),
    ]))

    /// Sessions of one agent in one folder, and an agent with a long name.
    static let sameFolder = state(input(.working(.many(3)), [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 14, label: "wiki", cause: .working, hint: SessionHint(name: "wiki-1d", terminal: "ttys001")),
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .backgroundJob(1), minutes: 89, label: "wiki", cause: .working, hint: SessionHint(name: "speaker-grille-spacing")),
        Agent(id: "claude", name: "Claude Code", state: .waitingForUser, reason: .asksPermission, minutes: 89, label: "wiki", hint: SessionHint(terminal: "ttys004")),
        Agent(id: "claude", name: "Claude Code", state: .waitingForUser, reason: .asksPermission, minutes: 0.2, label: "wiki"),
        Agent(id: "user:tool", name: "twenty-character-cli", state: .working, reason: .runningCommand(12), minutes: 89, label: "caffeinagent", cause: .working),
        Agent(id: "user:other", name: "twenty-character-two", minutes: 0.2),
        Agent(id: "codex", name: "Codex", minutes: 13),
    ]))

    static let noAgent = state(input(.noAgents))

    /// Three sessions of one agent at work, and its idle ones.
    static let grouped = state(input(.working(.many(3)), [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 6.5, label: "wiki", cause: .working, hint: SessionHint(name: "wiki-6e", terminal: "ttys001")),
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 6.4, label: "wiki", cause: .working, hint: SessionHint(name: "speaker-grille-spacing", terminal: "ttys002")),
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 6.3, label: "wiki", cause: .working, hint: SessionHint(name: "wiki-1d", terminal: "ttys003")),
    ] + idleClaude + [
        Agent(id: "codex", name: "Codex", minutes: 6),
        Agent(id: "antigravity", name: "Antigravity", minutes: 13 * 60),
    ]))

    /// Sessions that wait next to sessions that work.
    static let mixed = state(input(.working(.many(2)), [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 14, label: "wiki", cause: .working, hint: SessionHint(name: "wiki-6e")),
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .runningCommand(3), minutes: 3, label: "site", cause: .working),
        Agent(id: "claude", name: "Claude Code", state: .waitingForUser, reason: .asksPermission, minutes: 0.2, label: "notes", cause: .waitingForUser),
        Agent(id: "codex", name: "Codex", state: .waitingForUser, reason: .asksPermission, minutes: 3, label: "website", cause: .waitingForUser),
    ] + idleClaude.prefix(2) + [
        Agent(id: "antigravity", name: "Antigravity", minutes: 13 * 60),
    ]))

    /// Only idle sessions. The user can open the first group.
    static let idleGroups = state(input(.idle(.many(11)), (1...10).map {
        Agent(id: "claude", name: "Claude Code", minutes: Double($0) * 7, hint: SessionHint(name: $0 % 3 == 0 ? nil : "wiki-\($0)e", terminal: "ttys00\($0)"))
    } + [
        Agent(id: "codex", name: "Codex", minutes: 6, hint: SessionHint(terminal: "ttys011")),
        Agent(id: "codex", name: "Codex", minutes: 50, hint: SessionHint(terminal: "ttys012")),
        Agent(id: "antigravity", name: "Antigravity", minutes: 13 * 60),
    ]))

    /// A session with a name of 40 characters, and one that asks.
    static let longLabel = state(input(.working(.many(2)), [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .runningCommand(3), minutes: 3, label: "wiki", cause: .working, hint: SessionHint(name: "rewrite-the-onboarding-flow-for-new-team")),
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 6, label: "wiki", cause: .working, hint: SessionHint(name: "wiki-6e")),
        Agent(id: "claude", name: "Claude Code", state: .waitingForUser, reason: .asksPermission, minutes: 3, label: "wiki", cause: .waitingForUser, hint: SessionHint(name: "speaker-grille-spacing")),
        Agent(id: "codex", name: "Codex", minutes: 6),
    ]))

    static let off = state(input(.switchedOff, [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 12, label: "wiki"),
        Agent(id: "codex", name: "Codex", minutes: 40),
    ]))

    /// Paused for an hour while an agent works: the rows keep their states.
    static let paused = paused(.oneHour)
    static let pausedUntilTomorrow = paused(.untilTomorrow)

    private static func paused(_ choice: PauseChoice) -> PanelState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let until = Pause.deadline(for: choice, now: now, calendar: calendar)
        var input = Self.input(.paused(until: until), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 12, label: "wiki"),
            Agent(id: "codex", name: "Codex", minutes: 40),
        ])
        input.pausedUntil = until
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        return state(input)
    }

    /// The Mac stays reachable with no agent at work, on battery.
    static let reachable = reachable(lidClosedNeedsSetup: false)
    static let reachableNoHelper = reachable(lidClosedNeedsSetup: true)

    private static func reachable(lidClosedNeedsSetup: Bool) -> PanelState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let until = now.addingTimeInterval(2 * 3600)
        var input = Self.input(.reachable(until: until), [
            Agent(id: "claude", name: "Claude Code", minutes: 12),
            Agent(id: "codex", name: "Codex", minutes: 82),
        ])
        input.reachableUntil = until
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        input.onBattery = true
        input.batteryPercent = 58
        input.lidClosedNeedsSetup = lidClosedNeedsSetup
        return state(input)
    }

    /// A command that runs and a timed hold from the command line, with
    /// no agent at work.
    static let manualHolds: PanelState = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var input = Self.input(.manualHold(.many(2)), [Agent(id: "claude", name: "Claude Code", minutes: 12)])
        input.decision.manualHolds = [
            ManualHold.command(id: "0a1b2c3d", holder: ProcessIdentity(pid: 900, startTime: 0), command: "ffmpeg", now: now.addingTimeInterval(-12 * 60)),
            ManualHold.timed(id: "4e5f6a7b", length: 2 * 3600, reason: "Nightly backup", now: now.addingTimeInterval(-600)),
        ]
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        return state(input)
    }()

    /// A job of "Wake for jobs" that runs after the alarm woke the Mac,
    /// and the wake for the next one.
    static let jobHold: PanelState = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var input = Self.input(.scheduledJob(.one("backup.sh")), [Agent(id: "claude", name: "Claude Code", minutes: 12)])
        let alarm = now.addingTimeInterval(-180).timeIntervalSince1970
        input.decision.jobHolds = [JobHold(
            id: "crontab:backup@1", jobID: "crontab:backup", source: .crontab, name: "backup.sh", start: alarm, fireAt: alarm + 60,
            startGrace: 240, cap: 1800, seenAt: alarm + 62
        )]
        input.wakeAlarm = JobAlarm(at: now.addingTimeInterval(6 * 3600 - 60), fireAt: now.addingTimeInterval(6 * 3600), jobID: "launchd:com.example.report", jobName: "com.example.report")
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        return state(input)
    }()

    /// Nothing keeps the Mac awake, and a wake is set for the night.
    static let wakeSet: PanelState = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var input = Self.input(.idle(.one("Claude Code")), [Agent(id: "claude", name: "Claude Code", minutes: 12)])
        input.wakeAlarm = JobAlarm(at: now.addingTimeInterval(6 * 3600 - 60), fireAt: now.addingTimeInterval(6 * 3600), jobID: "crontab:backup", jobName: "backup.sh")
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        return state(input)
    }()

    static let safetyStop: PanelState = {
        var input = Self.input(.safetyStop(.batteryLow(percent: 20)), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 48, label: "wiki"),
            Agent(id: "codex", name: "Codex", minutes: 40),
        ])
        input.settings.batteryFloorPercent = 20
        return state(input)
    }()

    static let tooHot = state(input(.safetyStop(.tooHot)))

    /// On battery, with the line of the battery: far from the floor, close to it, and stopped.
    static let onBattery = onBattery(percent: 58)
    static let onBatteryNearFloor = onBattery(percent: 27)
    static let onBatteryStopped: PanelState = {
        var input = Self.input(.safetyStop(.batteryLow(percent: 19)), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 82, label: "wiki"),
            Agent(id: "codex", name: "Codex", minutes: 40),
        ])
        input.onBattery = true
        input.batteryPercent = 19
        return state(input)
    }()

    /// The battery floor is off, and the battery is low.
    static let onBatteryNoLimit = onBattery(percent: 9, floorEnabled: false)

    private static func onBattery(percent: Int, floorEnabled: Bool = true) -> PanelState {
        var input = Self.input(.working(.one("Claude Code")), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 82, label: "wiki", cause: .working),
            Agent(id: "codex", name: "Codex", minutes: 40),
        ])
        input.onBattery = true
        input.batteryPercent = percent
        input.settings.batteryFloorEnabled = floorEnabled
        return state(input)
    }

    static let lidClosedNotSetUp: PanelState = {
        var input = Self.input(.working(.one("Claude Code")), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .backgroundJob(1), minutes: 100, label: "wiki", cause: .working),
        ])
        input.lidClosedNeedsSetup = true
        return state(input)
    }()

    static let helperSwitchedOff: PanelState = {
        var input = Self.input(.alwaysOn)
        input.mode = .always
        input.flagLeftOn = true
        return state(input)
    }()

    static let helperNotResponding: PanelState = {
        var input = Self.input(.working(.one("Claude Code")), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 12, label: "wiki", cause: .working),
        ])
        input.helperNotResponding = true
        return state(input)
    }()

    /// The Mac slept under an agent, and the menu says why.
    static let sleptAnyway: PanelState = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var input = Self.input(.working(.one("Claude Code")), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 5, label: "wiki", cause: .working),
        ])
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        input.sleepNote = SleepNote(at: now.addingTimeInterval(-6 * 3600), reason: .lidClosedNoHelper)
        return state(input)
    }()

    /// The closed lid limit ended the hold, and the lid is still closed
    /// on battery: seen on a second display.
    static let closedLidStopped: PanelState = {
        var input = Self.input(.safetyStop(.closedLid(.time(seconds: 3 * 3600))), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 190, label: "wiki"),
        ])
        input.onBattery = true
        input.batteryPercent = 71
        return state(input)
    }()

    /// The lid is open again after the closed lid limit let the Mac sleep.
    static let sleptClosedLid: PanelState = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var input = Self.input(.working(.one("Claude Code")), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 5, label: "wiki", cause: .working),
        ])
        input.calendar = calendar
        input.locale = Locale(identifier: "en_GB")
        input.sleepNote = SleepNote(
            at: now.addingTimeInterval(-6 * 3600), reason: .closedLidLimit(.time(seconds: 3 * 3600), working: .one("Claude Code"))
        )
        return state(input)
    }()

    /// Every state by name, for the tests and the offscreen pictures.
    static let all: [(name: String, state: PanelState)] = [
        ("working", working), ("waiting", waiting), ("all-idle", allIdle), ("same-folder", sameFolder), ("no-agent", noAgent),
        ("grouped", grouped), ("mixed", mixed), ("idle-groups", idleGroups), ("long-label", longLabel),
        ("off", off), ("paused", paused), ("safety-stop", safetyStop), ("too-hot", tooHot),
        ("on-battery", onBattery), ("on-battery-near-floor", onBatteryNearFloor), ("on-battery-stopped", onBatteryStopped), ("on-battery-no-limit", onBatteryNoLimit),
        ("reachable", reachable), ("reachable-no-helper", reachableNoHelper), ("lid-closed", lidClosedNotSetUp),
        ("helper-off", helperSwitchedOff), ("helper-silent", helperNotResponding),
        ("slept-anyway", sleptAnyway), ("manual-holds", manualHolds), ("job-hold", jobHold), ("wake-set", wakeSet),
        ("closed-lid-stopped", closedLidStopped), ("slept-closed-lid", sleptClosedLid),
    ]

    /// One agent for each mark, to check the marks.
    static let everyMark = state(input(.idle(.many(26)), AgentLogo.markByAgentID.keys.sorted().map { Agent(id: $0, name: $0) }))
}
#endif
