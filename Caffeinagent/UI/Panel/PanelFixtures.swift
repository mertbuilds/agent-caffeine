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
        var input = PanelInput(decision: HoldDecision(hold: headline.keepsAwake, lidClosedFlag: false, headline: headline, perAgent: holds))
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

    static let off = state(input(.switchedOff, [
        Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 12, label: "wiki"),
        Agent(id: "codex", name: "Codex", minutes: 40),
    ]))

    static let safetyStop: PanelState = {
        var input = Self.input(.safetyStop(.batteryLow(percent: 20)), [
            Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 48, label: "wiki"),
            Agent(id: "codex", name: "Codex", minutes: 40),
        ])
        input.settings.batteryFloorPercent = 20
        return state(input)
    }()

    static let tooHot = state(input(.safetyStop(.tooHot)))

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

    static let trialEnding: PanelState = {
        var input = Self.input(.finishedRecently(.one("Claude Code")), [Agent(id: "claude", name: "Claude Code", minutes: 1)])
        input.entitlement = .trial(daysLeft: 2)
        return state(input)
    }()

    static let trialOver: PanelState = {
        var input = Self.input(.notEntitled(.trialOver), [Agent(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 5, label: "wiki")])
        input.entitlement = .expired(.trialOver)
        return state(input)
    }()

    /// Every state by name, for the tests and the offscreen pictures.
    static let all: [(name: String, state: PanelState)] = [
        ("working", working), ("waiting", waiting), ("all-idle", allIdle), ("same-folder", sameFolder), ("no-agent", noAgent),
        ("off", off), ("safety-stop", safetyStop), ("too-hot", tooHot), ("lid-closed", lidClosedNotSetUp),
        ("helper-off", helperSwitchedOff), ("trial-ending", trialEnding), ("trial-over", trialOver),
    ]

    /// One agent for each mark, to check the marks.
    static let everyMark = state(input(.idle(.many(26)), AgentLogo.markByAgentID.keys.sorted().map { Agent(id: $0, name: $0) }))
}
#endif
