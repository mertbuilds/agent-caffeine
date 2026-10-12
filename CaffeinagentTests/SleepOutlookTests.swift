import XCTest

final class SleepOutlookTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)

    private typealias Step = (seconds: TimeInterval, readings: [AgentReading])

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    private func reading(_ id: String, _ name: String, _ level: AgentDefinition.Level, _ state: WorkState, pid: Int32) -> AgentReading {
        let reason: VerdictReason
        switch state {
        case .working: reason = .reportsBusy
        case .waitingForUser: reason = .asksPermission
        case .idle: reason = .atPrompt
        }
        return AgentReading(
            agentID: id, displayName: name, level: level, kind: .cli, identity: ProcessIdentity(pid: pid, startTime: 1_791_196_400),
            hasLiveSession: false, verdict: AgentVerdict(state: state, confidence: .reported, reason: reason)
        )
    }

    private func claude(_ state: WorkState, pid: Int32 = 1) -> AgentReading { reading("claude", "Claude Code", .state, state, pid: pid) }
    private func opencode(_ state: WorkState, pid: Int32 = 3) -> AgentReading { reading("opencode", "opencode", .activity, state, pid: pid) }

    private func run(
        _ steps: [Step], mode: AwakeMode = .agentWorking, pausedUntil: Date? = nil, reachableUntil: Date? = nil,
        settings: DetectionSettings = DetectionSettings(), context: FrameContext = FrameContext(), mayHold: Bool = true
    ) -> [(seconds: TimeInterval, decision: HoldDecision)] {
        var memory = PolicyMemory()
        return steps.map { step in
            let (decision, next) = HoldPolicy.decide(
                readings: step.readings, memory: memory, mode: mode, enabled: true, pausedUntil: pausedUntil, reachableUntil: reachableUntil,
                safety: nil, settings: settings, context: context, mayHold: mayHold, now: at(step.seconds)
            )
            memory = next
            return (step.seconds, decision)
        }
    }

    /// The outlook 4 seconds into the wait of opencode, next to the others.
    private func outlook(
        with others: [AgentReading] = [], mode: AwakeMode = .agentWorking, pausedUntil: Date? = nil, reachableUntil: Date? = nil,
        settings: DetectionSettings = DetectionSettings(), context: FrameContext = FrameContext(), mayHold: Bool = true,
        mac: MacSleepState = MacSleepState()
    ) -> SleepOutlook {
        let readings = others + [opencode(.waitingForUser)]
        let decision = run(
            [(0, readings), (4, readings)], mode: mode, pausedUntil: pausedUntil, reachableUntil: reachableUntil,
            settings: settings, context: context, mayHold: mayHold
        )[1].decision
        return SleepOutlook(decision, mac: mac, now: at(4))
    }

    private let lidClosedOnBattery = MacSleepState(lidClosed: true, onBattery: true, flagInUse: true)

    // MARK: Outcomes

    func testAnotherAgentThatHoldsSaysNothing() {
        XCTAssertEqual(outlook(with: [claude(.working)]), .silent, "Claude Code works")
        XCTAssertEqual(outlook(with: [claude(.working)], mac: lidClosedOnBattery), .silent, "Also with the lid closed")
        // Claude Code worked at 0 and 4 s and holds as "finished a moment ago".
        let story: [Step] = [(0, [claude(.working), opencode(.waitingForUser)]), (4, [claude(.idle), opencode(.waitingForUser)])]
        let finished = run(story)[1].decision
        XCTAssertEqual(finished.perAgent.map(\.cause), [.finishedRecently, .waitingForUser])
        XCTAssertEqual(SleepOutlook(finished, mac: MacSleepState(), now: at(4)), .silent)
    }

    func testAnotherAgentThatWaitsCountsWithItsOwnHold() {
        let story: [Step] = [
            (0, [opencode(.waitingForUser)]),
            (100, [opencode(.waitingForUser), claude(.waitingForUser)]),
            (104, [opencode(.waitingForUser), claude(.waitingForUser)]),
        ]
        let decision = run(story)[2].decision
        XCTAssertEqual(decision.waitingEnds, at(400), "Claude Code began to wait at 100 s")
        XCTAssertEqual(SleepOutlook(decision, mac: MacSleepState(), now: at(104)), .letsGo(after: 296, then: .unknown))
    }

    func testLastHolderWithTheLidClosedOnBatterySleeps() {
        XCTAssertEqual(outlook(mac: lidClosedOnBattery), .sleeps(after: 296))
        var busy = lidClosedOnBattery
        busy.otherAppHolds = true
        busy.sleepTimerMinutes = 0
        XCTAssertEqual(outlook(mac: busy), .sleeps(after: 296), "macOS sleeps a Mac with the lid closed on battery all the same")
    }

    func testTheLidClosedIsCertainOnlyOnBatteryWithTheFlag() {
        var settings = DetectionSettings()
        settings.stayAwakeLidClosedOnBattery = false
        XCTAssertEqual(outlook(settings: settings, mac: lidClosedOnBattery), .letsGo(after: 296, then: .unknown), "The setting is off")
        XCTAssertEqual(outlook(mac: MacSleepState(lidClosed: true, onBattery: true)), .letsGo(after: 296, then: .unknown), "The flag is not set")
        XCTAssertEqual(outlook(mac: MacSleepState(lidClosed: true, flagInUse: true)), .letsGo(after: 296, then: .unknown), "On power")
        XCTAssertEqual(outlook(mac: MacSleepState(onBattery: true, flagInUse: true)), .letsGo(after: 296, then: .unknown), "The lid is open")
    }

    func testLastHolderWithTheLidOpenOnlyLetsGo() {
        XCTAssertEqual(outlook(), .letsGo(after: 296, then: .unknown))
        XCTAssertEqual(outlook(mac: MacSleepState(sleepTimerMinutes: 10)), .letsGo(after: 296, then: .sleepTimer(minutes: 10)))
        XCTAssertEqual(outlook(mac: MacSleepState(sleepTimerMinutes: 0)), .letsGo(after: 296, then: .neverSleeps))
        XCTAssertEqual(outlook(mac: MacSleepState(sleepTimerMinutes: 10, otherAppHolds: true)), .letsGo(after: 296, then: .otherAppHolds))
    }

    func testAModeOrATimerThatHoldsSaysNothing() {
        XCTAssertEqual(outlook(mode: .always, mac: lidClosedOnBattery), .silent, "always")
        XCTAssertEqual(outlook(mode: .agentOpen, mac: lidClosedOnBattery), .silent, "while an agent is open")
        XCTAssertEqual(outlook(reachableUntil: at(3600), mac: lidClosedOnBattery), .silent, "stay reachable")
        XCTAssertEqual(outlook(reachableUntil: at(2)), .letsGo(after: 296, then: .unknown), "stay reachable has ended")
        var remote = DetectionSettings()
        remote.stayAwakeForRemoteAccess = true
        XCTAssertEqual(outlook(settings: remote, context: FrameContext(remoteAccessDetected: true)), .silent, "phone access on power")
        XCTAssertEqual(
            outlook(settings: remote, context: FrameContext(onBattery: true, remoteAccessDetected: true)), .letsGo(after: 296, then: .unknown),
            "phone access does not hold on battery"
        )
        XCTAssertEqual(outlook(pausedUntil: at(3600), mac: lidClosedOnBattery), .silent, "paused")
        XCTAssertEqual(outlook(mayHold: false, mac: lidClosedOnBattery), .silent, "nothing holds while the Mac goes to sleep")
    }

    func testNothingIsSaidOnceTheHoldIsOver() {
        let decision = run([(0, [opencode(.waitingForUser)])])[0].decision
        XCTAssertEqual(SleepOutlook(decision, mac: MacSleepState(), now: at(299)), .letsGo(after: 1, then: .unknown))
        XCTAssertEqual(SleepOutlook(decision, mac: MacSleepState(), now: at(300)), .silent)
        let released = run([(0, [opencode(.waitingForUser)]), (300, [opencode(.waitingForUser)])])[1].decision
        XCTAssertNil(released.waitingEnds)
        XCTAssertEqual(SleepOutlook(released, mac: lidClosedOnBattery, now: at(300)), .silent)
    }

    /// An agent that reports its own state holds for the release time
    /// after its work, also past a short wait.
    func testAShortWaitEndsWithTheReleaseAfterWork() {
        var settings = DetectionSettings()
        settings.waitingHold = 30
        settings.releaseAfterState = 180
        let story: [Step] = [(0, [claude(.working)]), (10, [claude(.waitingForUser)])]
        XCTAssertEqual(run(story, settings: settings)[1].decision.waitingEnds, at(180))
        XCTAssertEqual(run(story)[1].decision.waitingEnds, at(310))
    }

    // MARK: Timeline

    /// opencode waits while Claude Code works, then Claude Code finishes
    /// and opencode is the last one that holds.
    func testOpencodeWaitsWhileClaudeCodeWorks() {
        var story: [Step] = stride(from: 0, to: 100, by: 5).map { ($0, [self.claude(.working), self.opencode($0 < 20 ? .working : .waitingForUser)]) }
        story += stride(from: 100, through: 330, by: 5).map { ($0, [self.claude(.idle), self.opencode(.waitingForUser)]) }
        for (seconds, decision) in run(story) {
            let outlook = SleepOutlook(decision, mac: MacSleepState(), now: at(seconds))
            let body = PanelText.sleepOutlook(outlook)
            let subtitle = PanelText.headline(decision.headline, outlook: outlook).subtitle
            switch seconds {
            case 0..<100:
                XCTAssertNil(body, "Claude Code works at \(seconds) s")
                XCTAssertEqual(subtitle, seconds < 20 ? "2 agents are working" : "Claude Code is working", "at \(seconds) s")
            case 100..<215:
                // Claude Code worked last at 95 s and holds for 120 s more.
                XCTAssertNil(body, "Claude Code finished a moment ago at \(seconds) s")
                XCTAssertEqual(subtitle, "opencode is waiting for you", "at \(seconds) s")
            case 215..<320:
                // opencode waits since 20 s, so its hold ends at 320 s.
                let minutes = seconds < 260 ? "2 more minutes" : "1 more minute"
                XCTAssertEqual(body, "Agent Caffeine keeps your Mac awake for \(minutes)", "at \(seconds) s")
                XCTAssertEqual(subtitle, "opencode is waiting for you, for at least \(minutes)", "at \(seconds) s")
            default:
                XCTAssertFalse(decision.hold, "at \(seconds) s")
                XCTAssertNil(body, "at \(seconds) s")
                XCTAssertEqual(subtitle, "opencode is waiting for you", "at \(seconds) s")
            }
        }
    }

    /// The same with a wait that outlasts the release time of Claude Code,
    /// so the line counts down over several minutes.
    func testTheLineAppearsWithTheTimeThatIsLeft() {
        var settings = DetectionSettings()
        settings.waitingHold = 600
        var story: [Step] = stride(from: 0, to: 100, by: 5).map { ($0, [self.claude(.working), self.opencode(.waitingForUser)]) }
        story += stride(from: 100, through: 600, by: 5).map { ($0, [self.claude(.idle), self.opencode(.waitingForUser)]) }
        var bodies: [String] = []
        for (seconds, decision) in run(story, settings: settings) {
            let body = PanelText.sleepOutlook(SleepOutlook(decision, mac: MacSleepState(), now: at(seconds)))
            XCTAssertEqual(body == nil, seconds < 215 || seconds >= 600, "at \(seconds) s")
            if let body, bodies.last != body { bodies.append(body) }
        }
        XCTAssertEqual(bodies, [7, 6, 5, 4, 3, 2].map { "Agent Caffeine keeps your Mac awake for \($0) more minutes" } + ["Agent Caffeine keeps your Mac awake for 1 more minute"])
    }

    // MARK: Words

    func testWords() {
        let cases: [(SleepOutlook, String?)] = [
            (.silent, nil),
            (.sleeps(after: 296), "Your Mac sleeps in 5 minutes"),
            (.sleeps(after: 300), "Your Mac sleeps in 5 minutes"),
            (.sleeps(after: 116), "Your Mac sleeps in 2 minutes"),
            (.sleeps(after: 60), "Your Mac sleeps in 1 minute"),
            (.sleeps(after: 1), "Your Mac sleeps in 1 minute"),
            (.sleeps(after: 5396), "Your Mac sleeps in 1 hour 30 minutes"),
            (.letsGo(after: 296, then: .unknown), "Agent Caffeine keeps your Mac awake for 5 more minutes"),
            (.letsGo(after: 296, then: .neverSleeps), "Agent Caffeine keeps your Mac awake for 5 more minutes"),
            (.letsGo(after: 296, then: .otherAppHolds), "Agent Caffeine keeps your Mac awake for 5 more minutes"),
            (.letsGo(after: 296, then: .sleepTimer(minutes: 1)), "Agent Caffeine keeps your Mac awake for 5 more minutes"),
            (.letsGo(after: 50, then: .unknown), "Agent Caffeine keeps your Mac awake for 1 more minute"),
            (.letsGo(after: 5396, then: .unknown), "Agent Caffeine keeps your Mac awake for 1 hour 30 minutes more"),
        ]
        for (outlook, text) in cases {
            XCTAssertEqual(PanelText.sleepOutlook(outlook), text, "\(outlook)")
            XCTAssertFalse(text?.contains("\u{2014}") ?? false)
        }
    }

    func testHeadlineWords() {
        let codex = HoldHeadline.waitingHeld(.one("Codex"))
        XCTAssertEqual(PanelText.headline(codex).subtitle, "Codex is waiting for you")
        XCTAssertEqual(PanelText.headline(codex, outlook: .sleeps(after: 200)).subtitle, "Codex is waiting for you, your Mac sleeps in 4 minutes")
        XCTAssertEqual(
            PanelText.headline(.waitingHeld(.many(2)), outlook: .letsGo(after: 200, then: .neverSleeps)).subtitle,
            "2 agents are waiting for you, for at least 4 more minutes"
        )
        XCTAssertEqual(PanelText.headline(codex, outlook: .sleeps(after: 200)).title, "Your Mac stays awake")
        // No other headline takes the outlook.
        XCTAssertEqual(PanelText.headline(.working(.one("Codex")), outlook: .sleeps(after: 200)).subtitle, "Codex is working")
        XCTAssertEqual(PanelText.headline(.waitingReleased(.one("Codex")), outlook: .sleeps(after: 200)).subtitle, "Codex is waiting for you")
    }

    func testLogLineHasTimesOnly() {
        XCTAssertEqual(SleepOutlook.silent.logLine, "sleep outlook: nothing said")
        XCTAssertEqual(SleepOutlook.sleeps(after: 296).logLine, "sleep outlook: the Mac sleeps in 296 s")
        XCTAssertEqual(
            SleepOutlook.letsGo(after: 296, then: .neverSleeps).logLine,
            "sleep outlook: Agent Caffeine lets go in 296 s, macOS never sleeps on this power source"
        )
    }

    // MARK: The sleep timer of macOS

    func testSleepTimerOfThePowerSourceInUse() {
        let laptop: [String: Any] = [
            "AC Power": ["System Sleep Timer": 0, "Display Sleep Timer": 10],
            "Battery Power": ["System Sleep Timer": 1, "Display Sleep Timer": 2],
        ]
        XCTAssertEqual(SystemSleepTimer.sleepTimerMinutes(in: laptop, onBattery: false), 0, "Never on power")
        XCTAssertEqual(SystemSleepTimer.sleepTimerMinutes(in: laptop, onBattery: true), 1)
        let desktop: [String: Any] = ["AC Power": ["System Sleep Timer": 15]]
        XCTAssertEqual(SystemSleepTimer.sleepTimerMinutes(in: desktop, onBattery: false), 15)
        XCTAssertNil(SystemSleepTimer.sleepTimerMinutes(in: desktop, onBattery: true))
        XCTAssertNil(SystemSleepTimer.sleepTimerMinutes(in: ["AC Power": ["Display Sleep Timer": 10]], onBattery: false), "The display is not the Mac")
        XCTAssertNil(SystemSleepTimer.sleepTimerMinutes(in: [:], onBattery: false))
    }
}
