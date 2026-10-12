import XCTest

final class HoldPolicyTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)

    private typealias Step = (seconds: TimeInterval, readings: [AgentReading])

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    private func run(
        _ steps: [Step], mode: AwakeMode = .agentWorking, enabled: Bool = true,
        safety: SafetyStop? = nil, settings: DetectionSettings = DetectionSettings(), context: FrameContext = FrameContext()
    ) -> [(seconds: TimeInterval, decision: HoldDecision)] {
        var memory = PolicyMemory()
        return steps.map { step in
            let (decision, next) = HoldPolicy.decide(
                readings: step.readings, memory: memory, mode: mode, enabled: enabled,
                safety: safety, settings: settings, context: context, now: at(step.seconds)
            )
            memory = next
            return (step.seconds, decision)
        }
    }

    /// One step every 5 seconds.
    private func steps(from: TimeInterval = 0, to: TimeInterval, _ make: (TimeInterval) -> [AgentReading]) -> [Step] {
        stride(from: from, through: to, by: 5).map { ($0, make($0)) }
    }

    private func reading(_ id: String, _ name: String, _ level: AgentDefinition.Level, _ state: WorkState, pid: Int32, kind: AgentDefinition.Kind = .cli, live: Bool = false) -> AgentReading {
        let reason: VerdictReason
        switch state {
        case .working: reason = .reportsBusy
        case .waitingForUser: reason = .asksPermission
        case .idle: reason = .atPrompt
        }
        return AgentReading(
            agentID: id, displayName: name, level: level, kind: kind, identity: ProcessIdentity(pid: pid, startTime: 1_791_196_400),
            hasLiveSession: live, verdict: AgentVerdict(state: state, confidence: .reported, reason: reason)
        )
    }

    private func claude(_ state: WorkState, pid: Int32 = 1) -> AgentReading { reading("claude", "Claude Code", .state, state, pid: pid) }
    private func codex(_ state: WorkState, pid: Int32 = 2) -> AgentReading { reading("codex", "Codex", .state, state, pid: pid) }
    private func opencode(_ state: WorkState, pid: Int32 = 3) -> AgentReading { reading("opencode", "opencode", .activity, state, pid: pid) }
    private func codexApp(_ state: WorkState, live: Bool) -> AgentReading {
        reading("codex-desktop", "Codex", .state, state, pid: 4, kind: .desktop, live: live)
    }

    private func decide(_ readings: [AgentReading], mode: AwakeMode = .agentWorking, enabled: Bool = true,
                        safety: SafetyStop? = nil, settings: DetectionSettings = DetectionSettings(), context: FrameContext = FrameContext()) -> HoldDecision {
        run([(0, readings)], mode: mode, enabled: enabled, safety: safety, settings: settings, context: context)[0].decision
    }

    // MARK: Background commands after the turn

    /// The verdict counted the release time for a background command that
    /// went quiet, so the policy adds none: not then, and not when the
    /// command ends later and the session is at its prompt.
    func testNoReleaseTimeAfterABackgroundCommandWentQuiet() {
        func claude(_ state: WorkState, _ reason: VerdictReason) -> AgentReading {
            AgentReading(
                agentID: "claude", displayName: "Claude Code", level: .state, identity: ProcessIdentity(pid: 1, startTime: 1_791_196_400),
                verdict: AgentVerdict(state: state, confidence: .reported, reason: reason)
            )
        }
        let context = FrameContext(onBattery: true, batteryPercent: 94, lidClosed: true)
        let got = run(steps(to: 400) { t in
            switch t {
            case ..<300: return [claude(.working, .backgroundWork)]
            case ..<350: return [claude(.idle, .backgroundIdle(minutes: 5))]
            default: return [claude(.idle, .atPrompt)]
            }
        }, context: context)
        for (seconds, decision) in got {
            XCTAssertEqual(decision.hold, seconds < 300, "at \(seconds) s")
            XCTAssertEqual(decision.lidClosedFlag, seconds < 300, "at \(seconds) s")
            XCTAssertEqual(decision.perAgent.first?.cause, seconds < 300 ? .working : nil, "at \(seconds) s")
        }
        // An idle of any other kind keeps its release time.
        let plain = run(steps(to: 200) { t in [t < 50 ? claude(.working, .reportsBusy) : claude(.idle, .atPrompt)] })
        XCTAssertEqual(plain.first { !$0.decision.hold }?.seconds, 165)
    }

    // MARK: Pause

    private func paused(
        _ readings: [AgentReading], until: TimeInterval, at seconds: TimeInterval = 0, mode: AwakeMode = .agentWorking, enabled: Bool = true,
        safety: SafetyStop? = nil
    ) -> HoldDecision {
        HoldPolicy.decide(
            readings: readings, memory: PolicyMemory(), mode: mode, enabled: enabled, pausedUntil: at(until),
            safety: safety, settings: DetectionSettings(), context: FrameContext(), now: at(seconds)
        ).0
    }

    func testAPauseHoldsNothingAndNeverSetsTheSleepFlag() {
        for mode in AwakeMode.allCases {
            let decision = paused([claude(.working), codex(.waitingForUser)], until: 1800, mode: mode)
            XCTAssertFalse(decision.hold, "\(mode)")
            XCTAssertFalse(decision.lidClosedFlag, "\(mode)")
            XCTAssertEqual(decision.headline, .paused(until: at(1800)), "\(mode)")
            XCTAssertEqual(decision.perAgent.map(\.cause), [nil, nil], "\(mode)")
            // The rows still say what the agents do.
            XCTAssertEqual(decision.perAgent.map(\.reading.verdict.state), [.working, .waitingForUser], "\(mode)")
        }
    }

    func testAPauseIsOverAtItsTime() {
        XCTAssertEqual(paused([claude(.working)], until: 1800, at: 1799).headline, .paused(until: at(1800)))
        let after = paused([claude(.working)], until: 1800, at: 1800)
        XCTAssertEqual(after.headline, .working(.one("Claude Code")))
        XCTAssertTrue(after.hold)
        XCTAssertTrue(after.lidClosedFlag)
    }

    /// Safety, then the switch, then the pause.
    func testTheOrderOfTheStops() {
        let agents = [claude(.working)]
        XCTAssertEqual(paused(agents, until: 1800, safety: .tooHot).headline, .safetyStop(.tooHot))
        XCTAssertEqual(paused(agents, until: 1800, enabled: false).headline, .switchedOff)
        for decision in [paused(agents, until: 1800, safety: .tooHot), paused(agents, until: 1800, enabled: false)] {
            XCTAssertFalse(decision.hold)
            XCTAssertFalse(decision.lidClosedFlag)
        }
    }

    // MARK: Stay reachable

    private func reachable(
        _ readings: [AgentReading], until: TimeInterval = 3600, at seconds: TimeInterval = 0, mode: AwakeMode = .agentWorking, enabled: Bool = true,
        pausedUntil: TimeInterval? = nil, safety: SafetyStop? = nil,
        settings: DetectionSettings = DetectionSettings(), context: FrameContext = FrameContext()
    ) -> HoldDecision {
        HoldPolicy.decide(
            readings: readings, memory: PolicyMemory(), mode: mode, enabled: enabled, pausedUntil: pausedUntil.map(at), reachableUntil: at(until),
            safety: safety, settings: settings, context: context, now: at(seconds)
        ).0
    }

    func testStayReachableHoldsWithNoAgentAtWork() {
        for readings in [[], [claude(.idle)], [claude(.idle), codex(.idle)]] {
            let decision = reachable(readings)
            XCTAssertTrue(decision.hold)
            XCTAssertTrue(decision.lidClosedFlag, "With the helper it lasts over a closed lid")
            XCTAssertEqual(decision.headline, .reachable(until: at(3600)))
            XCTAssertEqual(decision.perAgent.map(\.cause), readings.map { _ in nil })
        }
        XCTAssertEqual(HoldHeadline.reachable(until: at(3600)).text, "Awake: stays reachable")
    }

    func testStayReachableWorksOnBattery() {
        let decision = reachable([], context: FrameContext(onBattery: true, batteryPercent: 60))
        XCTAssertTrue(decision.hold)
        XCTAssertTrue(decision.lidClosedFlag)
    }

    func testTheLidClosedFlagFollowsTheSetting() {
        var settings = DetectionSettings()
        settings.stayAwakeLidClosedOnBattery = false
        let decision = reachable([], settings: settings)
        XCTAssertTrue(decision.hold)
        XCTAssertFalse(decision.lidClosedFlag)
    }

    func testAnAgentThatHoldsIsNamedBeforeStayReachable() {
        XCTAssertEqual(reachable([claude(.working)]).headline, .working(.one("Claude Code")))
        XCTAssertEqual(reachable([codex(.waitingForUser)]).headline, .waitingHeld(.one("Codex")))
        XCTAssertEqual(reachable([], mode: .always).headline, .alwaysOn)
        XCTAssertEqual(reachable([claude(.idle)], mode: .agentOpen).headline, .open(.one("Claude Code")))
        // After the waiting hold ran out the Mac still stays awake.
        var memory = PolicyMemory()
        var last: HoldDecision?
        for seconds in stride(from: 0.0, through: 400, by: 100) {
            let (decision, next) = HoldPolicy.decide(
                readings: [codex(.waitingForUser)], memory: memory, mode: .agentWorking, enabled: true, reachableUntil: at(3600),
                safety: nil, settings: DetectionSettings(), context: FrameContext(), now: at(seconds)
            )
            (memory, last) = (next, decision)
        }
        XCTAssertEqual(last?.headline, .reachable(until: at(3600)))
        XCTAssertEqual(last?.hold, true)
    }

    func testStayReachableIsOverAtItsTime() {
        XCTAssertTrue(reachable([], at: 3599).hold)
        let after = reachable([], at: 3600)
        XCTAssertFalse(after.hold)
        XCTAssertFalse(after.lidClosedFlag)
        XCTAssertEqual(after.headline, .noAgents)
    }

    func testEveryStopEndsTheHoldOfStayReachable() {
        let stops: [(HoldDecision, HoldHeadline)] = [
            (reachable([], safety: .batteryLow(percent: 20)), .safetyStop(.batteryLow(percent: 20))),
            (reachable([], safety: .tooHot), .safetyStop(.tooHot)),
            (reachable([], enabled: false), .switchedOff),
            (reachable([], pausedUntil: 1800), .paused(until: at(1800))),
        ]
        for (decision, headline) in stops {
            XCTAssertEqual(decision.headline, headline)
            XCTAssertFalse(decision.hold, "\(headline)")
            XCTAssertFalse(decision.lidClosedFlag, "\(headline)")
        }
    }

    func testWithoutStayReachableNothingChanges() {
        XCTAssertEqual(decide([]).headline, .noAgents)
        XCTAssertEqual(decide([claude(.idle)]).headline, .idle(.one("Claude Code")))
    }

    // MARK: While an agent is working

    func testStateAgentHoldsForTheReleaseTime() {
        let story = steps(to: 300) { t in [self.claude(t <= 60 ? .working : .idle)] }
        for (seconds, decision) in run(story) {
            XCTAssertEqual(decision.hold, seconds < 180, "at \(seconds) s")
            let text = seconds <= 60 ? "Awake: Claude Code is working"
                : seconds < 180 ? "Awake: Claude Code finished a moment ago" : "Mac can sleep: Claude Code is idle"
            XCTAssertEqual(decision.headline.text, text, "at \(seconds) s")
            let cause: HoldCause? = seconds <= 60 ? .working : seconds < 180 ? .finishedRecently : nil
            XCTAssertEqual(decision.perAgent.map(\.cause), [cause], "at \(seconds) s")
        }
    }

    /// The verdict of an agent that is judged by its activity already
    /// counts the release time, so the policy adds none.
    func testActivityAgentReleasesWithItsVerdict() {
        let got = run([(0, [opencode(.working)]), (5, [opencode(.idle)])])
        XCTAssertEqual(got.map(\.decision.hold), [true, false])
        XCTAssertEqual(got.map(\.decision.headline.text), ["Awake: opencode is working", "Mac can sleep: opencode is idle"])
    }

    func testAgentThatWasNeverWorkingDoesNotHold() {
        XCTAssertFalse(decide([claude(.idle)]).hold)
        XCTAssertEqual(decide([claude(.idle), opencode(.idle)]).headline.text, "Mac can sleep: all agents are idle")
        XCTAssertEqual(decide([]).headline.text, "Mac can sleep: no agent is open")
    }

    /// Waits 5 minutes, then the Mac can sleep. Work starts the clock again.
    func testWaitingForTheUser() {
        var story: [Step] = [(0, [codex(.working)])]
        story += steps(from: 10, to: 400) { _ in [self.codex(.waitingForUser)] }
        story += [(405, [codex(.working)])]
        story += steps(from: 410, to: 800) { _ in [self.codex(.waitingForUser)] }
        for (seconds, decision) in run(story) {
            switch seconds {
            case 0, 405:
                XCTAssertEqual(decision.headline.text, "Awake: Codex is working", "at \(seconds) s")
            case 10..<310, 410..<710:
                XCTAssertTrue(decision.hold, "at \(seconds) s")
                XCTAssertEqual(decision.headline.text, "Awake: Codex is waiting for you", "at \(seconds) s")
                XCTAssertEqual(decision.perAgent.map(\.cause), [.waitingForUser], "at \(seconds) s")
            default:
                XCTAssertFalse(decision.hold, "at \(seconds) s")
                XCTAssertEqual(decision.headline.text, "Mac can sleep: Codex is waiting for you", "at \(seconds) s")
            }
        }
    }

    func testWaitingHoldIsAdjustable() {
        var settings = DetectionSettings()
        settings.waitingHold = 30
        settings.releaseAfterState = 10
        let story = steps(to: 60) { t in [self.codex(t == 0 ? .working : .waitingForUser)] }
        for (seconds, decision) in run(story, settings: settings) {
            XCTAssertEqual(decision.hold, seconds < 35, "at \(seconds) s")
        }
    }

    func testTwoAgentsOneStops() {
        let story = steps(to: 400) { t in
            [self.claude(t <= 50 ? .working : .idle, pid: 1), self.claude(t <= 200 ? .working : .idle, pid: 2)]
        }
        for (seconds, decision) in run(story) {
            XCTAssertEqual(decision.hold, seconds < 320, "at \(seconds) s")
            let text: String
            switch seconds {
            case ...50: text = "Awake: 2 agents are working"
            case ...200: text = "Awake: Claude Code is working"
            case ..<320: text = "Awake: Claude Code finished a moment ago"
            default: text = "Mac can sleep: all agents are idle"
            }
            XCTAssertEqual(decision.headline.text, text, "at \(seconds) s")
        }
    }

    func testTwoAgentsOneExits() {
        let got = run([(0, [claude(.working, pid: 1), opencode(.working)]), (5, [opencode(.working)]), (10, [])])
        XCTAssertEqual(got.map(\.decision.hold), [true, true, false])
        XCTAssertEqual(got.map(\.decision.headline.text), ["Awake: 2 agents are working", "Awake: opencode is working", "Mac can sleep: no agent is open"])
    }

    /// A process that is gone holds nothing, not even for the release time,
    /// and a new process with the same pid starts with no memory.
    func testProcessGone() {
        var memory = PolicyMemory()
        func step(_ seconds: TimeInterval, _ readings: [AgentReading]) -> HoldDecision {
            let (decision, next) = HoldPolicy.decide(readings: readings, memory: memory, mode: .agentWorking, enabled: true,
                                                     safety: nil, settings: DetectionSettings(), context: FrameContext(), now: at(seconds))
            memory = next
            return decision
        }
        XCTAssertTrue(step(0, [claude(.working)]).hold)
        XCTAssertFalse(step(5, []).hold)
        XCTAssertEqual(memory, PolicyMemory())
        var reused = claude(.idle)
        reused.identity = ProcessIdentity(pid: 1, startTime: 1_791_200_007)
        XCTAssertFalse(step(10, [reused]).hold)
    }

    // MARK: Other modes

    func testWhileAnAgentIsOpen() {
        let cases: [(name: String, readings: [AgentReading], hold: Bool, text: String)] = [
            ("nothing open", [], false, "Mac can sleep: no agent is open"),
            ("idle CLI", [claude(.idle)], true, "Awake: Claude Code is open"),
            ("two idle CLIs", [claude(.idle), opencode(.idle)], true, "Awake: 2 agents are open"),
            ("desktop app with no live session", [codexApp(.idle, live: false)], false, "Mac can sleep: Codex is idle"),
            ("desktop app with a live session", [codexApp(.idle, live: true)], true, "Awake: Codex is open"),
            ("desktop app that works", [codexApp(.working, live: false)], true, "Awake: Codex is working"),
            ("work comes before open", [claude(.idle), opencode(.working)], true, "Awake: opencode is working"),
        ]
        for c in cases {
            let decision = decide(c.readings, mode: .agentOpen)
            XCTAssertEqual(decision.hold, c.hold, c.name)
            XCTAssertEqual(decision.headline.text, c.text, c.name)
        }
        XCTAssertEqual(decide([codexApp(.idle, live: true)], mode: .agentOpen).perAgent.map(\.cause), [.open])
        XCTAssertFalse(decide([codexApp(.idle, live: true)]).hold, "an open app holds nothing in the working mode")
    }

    func testAlways() {
        for readings in [[], [claude(.idle)], [claude(.working)]] {
            let decision = decide(readings, mode: .always)
            XCTAssertTrue(decision.hold)
            XCTAssertTrue(decision.lidClosedFlag)
            XCTAssertEqual(decision.headline.text, "Awake: always on")
        }
    }

    func testSwitchedOff() {
        for mode in AwakeMode.allCases {
            let decision = decide([claude(.working)], mode: mode, enabled: false, context: FrameContext(remoteAccessDetected: true))
            XCTAssertFalse(decision.hold, "\(mode)")
            XCTAssertFalse(decision.lidClosedFlag, "\(mode)")
            XCTAssertEqual(decision.headline.text, "Mac can sleep: Agent Caffeine is off", "\(mode)")
            XCTAssertEqual(decision.perAgent.map(\.cause), [nil], "\(mode)")
        }
    }

    // MARK: Safety, remote access, lid

    func testSafetyStop() {
        let cases: [(stop: SafetyStop, text: String)] = [
            (.batteryLow(percent: 20), "Sleeping allowed: battery at 20%"),
            (.batteryLow(percent: 7), "Sleeping allowed: battery at 7%"),
            (.tooHot, "Sleeping allowed: the Mac is too hot"),
        ]
        for c in cases {
            for mode in AwakeMode.allCases {
                let decision = decide([claude(.working)], mode: mode, safety: c.stop, context: FrameContext(onBattery: false, remoteAccessDetected: true))
                XCTAssertFalse(decision.hold, "\(c.stop) \(mode)")
                XCTAssertFalse(decision.lidClosedFlag, "\(c.stop) \(mode)")
                XCTAssertEqual(decision.headline.text, c.text, "\(c.stop) \(mode)")
                XCTAssertEqual(decision.perAgent.map(\.cause), [nil], "\(c.stop) \(mode)")
            }
        }
    }

    /// The release time keeps counting under a safety stop.
    func testSafetyStopEnds() {
        var memory = PolicyMemory()
        func step(_ seconds: TimeInterval, _ state: WorkState, safety: SafetyStop?) -> Bool {
            let (decision, next) = HoldPolicy.decide(readings: [claude(state)], memory: memory, mode: .agentWorking, enabled: true,
                                                     safety: safety, settings: DetectionSettings(), context: FrameContext(), now: at(seconds))
            memory = next
            return decision.hold
        }
        XCTAssertFalse(step(0, .working, safety: .tooHot))
        XCTAssertFalse(step(5, .idle, safety: .tooHot))
        XCTAssertTrue(step(10, .idle, safety: nil))
        XCTAssertFalse(step(120, .idle, safety: nil))
    }

    func testRemoteAccessHoldCanBeSwitchedOff() {
        var settings = DetectionSettings()
        settings.stayAwakeForRemoteAccess = false
        let decision = decide([], settings: settings, context: FrameContext(onBattery: false, remoteAccessDetected: true))
        XCTAssertFalse(decision.hold)
        XCTAssertEqual(decision.headline.text, "Mac can sleep: no agent is open")
    }

    func testRemoteAccess() {
        let onPower = FrameContext(onBattery: false, remoteAccessDetected: true)
        let onBattery = FrameContext(onBattery: true, batteryPercent: 80, remoteAccessDetected: true)
        let cases: [(name: String, readings: [AgentReading], mode: AwakeMode, context: FrameContext, hold: Bool, text: String)] = [
            ("on power, no agent", [], .agentWorking, onPower, true, "Awake: reachable while plugged in"),
            ("on power, idle agent", [claude(.idle)], .agentWorking, onPower, true, "Awake: reachable while plugged in"),
            ("on power, working agent", [claude(.working)], .agentWorking, onPower, true, "Awake: Claude Code is working"),
            ("on power, open mode", [], .agentOpen, onPower, true, "Awake: reachable while plugged in"),
            ("on battery, no agent", [], .agentWorking, onBattery, false, "Mac can sleep: no agent is open"),
            ("on battery, idle agent", [claude(.idle)], .agentWorking, onBattery, false, "Mac can sleep: Claude Code is idle"),
            ("on battery, working agent", [claude(.working)], .agentWorking, onBattery, true, "Awake: Claude Code is working"),
        ]
        for c in cases {
            let decision = decide(c.readings, mode: c.mode, context: c.context)
            XCTAssertEqual(decision.hold, c.hold, c.name)
            XCTAssertEqual(decision.headline.text, c.text, c.name)
        }
    }

    func testLidClosedFlag() {
        var off = DetectionSettings()
        off.stayAwakeLidClosedOnBattery = false
        let cases: [(name: String, state: WorkState, settings: DetectionSettings, onBattery: Bool, safety: SafetyStop?, want: Bool)] = [
            ("work on wall power", .working, DetectionSettings(), false, nil, true),
            ("work on battery", .working, DetectionSettings(), true, nil, true),
            ("no work", .idle, DetectionSettings(), true, nil, false),
            ("setting off, wall power", .working, off, false, nil, false),
            ("setting off, battery", .working, off, true, nil, false),
            ("safety stop", .working, DetectionSettings(), true, .batteryLow(percent: 20), false),
        ]
        for c in cases {
            let decision = decide([claude(c.state)], safety: c.safety, settings: c.settings, context: FrameContext(onBattery: c.onBattery, batteryPercent: 50))
            XCTAssertEqual(decision.lidClosedFlag, c.want, c.name)
        }
    }

    func testWithTheBatteryFloorOffAnEmptyBatteryKeepsTheHold() {
        var settings = DetectionSettings()
        settings.batteryFloorEnabled = false
        var monitor = SafetyMonitor()
        monitor.batteryFloorEnabled = settings.batteryFloorEnabled
        for (thermal, hold) in [(ProcessInfo.ThermalState.nominal, true), (.serious, false)] {
            let safety = monitor.update(SafetyInputs(batteryPercent: 1, onBattery: true, thermalState: thermal))
            let decision = decide([claude(.working)], safety: safety, settings: settings, context: FrameContext(onBattery: true, batteryPercent: 1))
            XCTAssertEqual(decision.hold, hold, "\(thermal)")
            XCTAssertEqual(decision.lidClosedFlag, hold, "\(thermal)")
        }
    }

    // MARK: After a sleep

    func testNothingStartsAHoldWhileItMayNot() {
        let reachableUntil = at(3600)
        let cases: [(name: String, readings: [AgentReading], mode: AwakeMode, reachable: Date?, headline: HoldHeadline)] = [
            ("working", [claude(.working)], .agentWorking, nil, .idle(.one("Claude Code"))),
            ("two agents", [claude(.working), codex(.idle)], .agentWorking, nil, .idle(.many(2))),
            ("waiting", [claude(.waitingForUser)], .agentWorking, nil, .waitingReleased(.one("Claude Code"))),
            ("open", [claude(.idle)], .agentOpen, nil, .idle(.one("Claude Code"))),
            ("always", [], .always, nil, .noAgents),
            ("reachable", [], .agentWorking, reachableUntil, .noAgents),
        ]
        for c in cases {
            func decide(mayHold: Bool) -> HoldDecision {
                HoldPolicy.decide(
                    readings: c.readings, memory: PolicyMemory(), mode: c.mode, enabled: true, reachableUntil: c.reachable,
                    safety: nil, settings: DetectionSettings(), context: FrameContext(), mayHold: mayHold, now: at(0)
                ).0
            }
            XCTAssertTrue(decide(mayHold: true).hold, c.name)
            let decision = decide(mayHold: false)
            XCTAssertFalse(decision.hold, c.name)
            XCTAssertFalse(decision.lidClosedFlag, c.name)
            XCTAssertEqual(decision.headline, c.headline, c.name)
            XCTAssertEqual(decision.perAgent.map(\.cause), c.readings.map { _ in nil }, c.name)
            XCTAssertNil(decision.headline.awakeReason, c.name)
        }
        // A stop is still named.
        let stopped = HoldPolicy.decide(
            readings: [claude(.working)], memory: PolicyMemory(), mode: .agentWorking, enabled: true, pausedUntil: at(60),
            safety: nil, settings: DetectionSettings(), context: FrameContext(), mayHold: false, now: at(0)
        ).0
        XCTAssertEqual(stopped.headline, .paused(until: at(60)))
    }

    // MARK: Rules

    func testIgnoredAgent() {
        var settings = DetectionSettings()
        settings.agentRules = ["claude": .ignore]
        let ignored = AgentReading(agentID: "claude", displayName: "Claude Code", level: .state, identity: ProcessIdentity(pid: 1, startTime: 0),
                                   verdict: AgentVerdict(state: .idle, confidence: .reported, reason: .ignoredByRule))
        for mode in [AwakeMode.agentOpen, .agentWorking] {
            let alone = decide([ignored], mode: mode, settings: settings)
            XCTAssertFalse(alone.hold, "\(mode)")
            XCTAssertEqual(alone.headline.text, "Mac can sleep: no agent is open", "\(mode)")
            XCTAssertEqual(alone.perAgent.count, 1)
        }
        XCTAssertEqual(decide([ignored, opencode(.idle)], settings: settings).headline.text, "Mac can sleep: opencode is idle")
        XCTAssertEqual(decide([ignored, opencode(.idle)], mode: .agentOpen, settings: settings).headline.text, "Awake: opencode is open")
    }

    /// Evidence frames go through the verdicts into the decision, as the
    /// app and a replayed log do.
    func testReplayWithRules() {
        var settings = DetectionSettings()
        settings.agentRules = ["claude": .ignore, "opencode": .alwaysWorkingWhileOpen]
        let report = StateReport(state: .working, since: nil, observedAt: at(0), source: .claudeSessionFile, detail: nil)
        let claude = AgentEvidence(agentID: "claude", displayName: "Claude Code", level: .state, pid: 1, startTime: 1_791_196_400, reported: report)
        let opencode = AgentEvidence(agentID: "opencode", displayName: "opencode", level: .activity, pid: 3, startTime: 1_791_196_400)
        let frames = [
            EvidenceFrame(at: at(0), agents: [claude]),
            EvidenceFrame(at: at(5), agents: [claude, opencode]),
            EvidenceFrame(at: at(10), agents: [claude]),
        ]
        var agentMemory: [ProcessIdentity: AgentMemory] = [:]
        var policyMemory = PolicyMemory()
        var texts: [String] = []
        for frame in frames {
            let (readings, nextAgents) = VerdictRules.readings(for: frame, memory: agentMemory, settings: settings)
            let (decision, nextPolicy) = HoldPolicy.decide(readings: readings, memory: policyMemory, mode: .agentWorking, enabled: true,
                                                           safety: nil, settings: settings, context: frame.context, now: frame.at)
            agentMemory = nextAgents
            policyMemory = nextPolicy
            texts.append(decision.headline.text)
        }
        XCTAssertEqual(texts, ["Mac can sleep: no agent is open", "Awake: opencode is working", "Mac can sleep: no agent is open"])
    }

    // MARK: Text

    func testHeadlineText() {
        let cases: [(headline: HoldHeadline, text: String)] = [
            (.working(.one("Claude Code")), "Awake: Claude Code is working"),
            (.working(.many(2)), "Awake: 2 agents are working"),
            (.waitingHeld(.one("Codex")), "Awake: Codex is waiting for you"),
            (.waitingHeld(.many(2)), "Awake: 2 agents are waiting for you"),
            (.finishedRecently(.one("Codex")), "Awake: Codex finished a moment ago"),
            (.finishedRecently(.many(3)), "Awake: 3 agents finished a moment ago"),
            (.open(.one("Antigravity")), "Awake: Antigravity is open"),
            (.open(.many(4)), "Awake: 4 agents are open"),
            (.alwaysOn, "Awake: always on"),
            (.remoteAccess, "Awake: reachable while plugged in"),
            (.reachable(until: Self.start), "Awake: stays reachable"),
            (.idle(.one("opencode")), "Mac can sleep: opencode is idle"),
            (.idle(.many(2)), "Mac can sleep: all agents are idle"),
            (.waitingReleased(.one("Codex")), "Mac can sleep: Codex is waiting for you"),
            (.waitingReleased(.many(2)), "Mac can sleep: 2 agents are waiting for you"),
            (.noAgents, "Mac can sleep: no agent is open"),
            (.safetyStop(.batteryLow(percent: 20)), "Sleeping allowed: battery at 20%"),
            (.safetyStop(.weakCharger(percent: 20)), "Sleeping allowed: weak charger, battery at 20%"),
            (.safetyStop(.tooHot), "Sleeping allowed: the Mac is too hot"),
            (.switchedOff, "Mac can sleep: Agent Caffeine is off"),
            (.paused(until: Self.start), "Mac can sleep: Agent Caffeine is paused"),
        ]
        for c in cases {
            XCTAssertEqual(c.headline.text, c.text)
            XCTAssertEqual(c.headline.keepsAwake, c.text.hasPrefix("Awake:"), c.text)
            XCTAssertFalse(c.text.contains("\u{2014}"))
        }
    }
}
