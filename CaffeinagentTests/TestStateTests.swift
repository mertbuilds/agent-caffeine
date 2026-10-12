import XCTest

final class TestStateTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_791_200_000)
    /// In every text a user or an agent could have written.
    private static let secret = "SECRETWORD"

    private func at(_ seconds: TimeInterval) -> Date { Self.start.addingTimeInterval(seconds) }

    /// Every field filled, and every free text of the app carries the secret.
    private func fullInput() -> TestStateInput {
        let secret = Self.secret
        let claude = ProcessIdentity(pid: 100, startTime: 1)
        let tool = ProcessIdentity(pid: 200, startTime: 2)
        let readings = [
            AgentReading(
                agentID: "claude", displayName: "Claude \(secret)", level: .state, identity: claude,
                verdict: AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
            ),
            AgentReading(
                agentID: "user:/Users/\(secret)/bin/\(secret)", displayName: secret, level: .generic, identity: tool,
                verdict: AgentVerdict(state: .idle, confidence: .inferredWeak, reason: .noActivity(minutes: 3))
            ),
        ]
        let evidence = [
            AgentEvidence(
                agentID: "claude", displayName: secret, level: .state, role: .engine, pid: 100, startTime: 1,
                reported: StateReport(state: .working, since: nil, observedAt: at(0), source: .claudeSessionFile, detail: secret)
            ),
        ]
        let frame = EvidenceFrame(at: at(0), agents: evidence, context: FrameContext(onBattery: true, batteryPercent: 64, lidClosed: true, charging: false, offline: true))
        let job = ScheduledJob(id: "launchd:\(secret)", source: .launchd, name: secret, schedule: .calendar([]), enabled: true)
        let alarm = JobAlarm(at: at(600), fireAt: at(660), jobID: job.id, jobName: secret)
        let jobHold = JobHold(
            id: "\(job.id)@1", jobID: job.id, source: .launchd, name: secret, start: at(-30).timeIntervalSince1970,
            fireAt: at(30).timeIntervalSince1970, startGrace: 240, cap: 1800
        )
        let decision = HoldDecision(
            hold: true, lidClosedFlag: true, headline: .working(.one("Claude \(secret)")),
            perAgent: [AgentHold(reading: readings[0], cause: .working), AgentHold(reading: readings[1], cause: nil)],
            manualHolds: [ManualHold.timed(id: "0a1b2c3d", length: 600, reason: secret, now: at(0))],
            jobHolds: [jobHold]
        )
        // A closed-lid period of 610 seconds that reached its limit of 600.
        var closedLid = ClosedLidLimit()
        closedLid.timeLimit = 600
        let lidContext = FrameContext(onBattery: true, batteryPercent: 70, lidClosed: true)
        _ = closedLid.update(lidContext, holding: true, at: SampleTime(at: at(-700), awake: nil))
        _ = closedLid.update(lidContext, holding: true, at: SampleTime(at: at(-90), awake: nil))
        // Offline for 610 seconds, with a limit of 600.
        var offline = OfflineRule()
        offline.update(offline: true, at: SampleTime(at: at(-610), awake: 100))
        offline.update(offline: true, at: SampleTime(at: at(0), awake: 710))
        var notices = TestNoticeLog()
        notices.note(.waiting, at: at(-20))
        notices.note(.finished, at: at(-10))
        return TestStateInput(
            at: at(1), version: "1.0.3", build: "17", bundlePath: "/Applications/agent caffeine.app", pid: 4242,
            enabled: true, pausedUntil: at(900), reachableUntil: at(1800), mode: .agentWorking,
            decision: decision, frame: frame, assertionHeld: true, helper: .enabled, setup: .ready, flagSet: true,
            lidAngle: 3.04, safety: .batteryLow(percent: 20), closedLid: closedLid, offline: offline, gate: WakeGate().code, wakeForJobs: true,
            jobs: JobWakeView(
                status: .alarmSet(alarm), runs: [JobRun(job: job, fireAt: at(660), tooOften: false)], alarm: alarm,
                history: [JobEvent(at: at(-5).timeIntervalSince1970, kind: .alarmSet, alarmAt: at(600).timeIntervalSince1970, job: secret, reason: nil)]
            ),
            notices: notices.events, chimeAt: at(-3)
        )
    }

    private func object(_ state: TestState) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(state.encoded())) as? [String: Any])
    }

    // MARK: Model

    func testStateSaysWhatTheAppDecided() throws {
        let state = TestState(fullInput())
        XCTAssertEqual(state.v, 1)
        XCTAssertEqual(state.at, at(1).timeIntervalSince1970)
        XCTAssertEqual(state.app, TestState.App(version: "1.0.3", build: "17", path: "/Applications/agent caffeine.app", pid: 4242))
        XCTAssertTrue(state.on)
        XCTAssertEqual(state.pausedUntil, at(900).timeIntervalSince1970)
        XCTAssertEqual(state.mode, "agentWorking")
        XCTAssertEqual(state.decision, TestState.Decision(hold: true, headline: "working", reason: nil, stop: false, assertion: true))
        XCTAssertEqual(state.flag, TestState.Flag(wanted: true, helper: "enabled", setup: "ready", set: true))
        XCTAssertEqual(state.power, TestState.Power(source: "battery", percent: 64, charging: false))
        XCTAssertEqual(state.lid, TestState.Lid(closed: true, angle: 3))
        XCTAssertEqual(state.safety, "batteryLow")
        XCTAssertEqual(state.closedLid, TestState.ClosedLid(
            since: at(-700).timeIntervalSince1970, heldSeconds: 610, percentAtStart: 70, limitSeconds: 600, limitDrop: 30, stop: "closedLidTime"
        ))
        XCTAssertEqual(state.network, TestState.Network(online: false, offlineSeconds: 610, limitSeconds: 600, agentsReleased: true))
        XCTAssertEqual(state.gate, "open")
        XCTAssertEqual(state.agents, [
            TestState.Agent(id: "claude", pid: 100, role: "engine", state: "working", why: "reportsBusy", level: "state", hold: "working"),
            TestState.Agent(id: "user", pid: 200, role: nil, state: "idle", why: "noActivity:3", level: "generic", hold: nil),
        ])
        XCTAssertEqual(state.holds, [TestState.Hold(id: "0a1b2c3d", kind: "timed", start: at(0).timeIntervalSince1970, end: at(600).timeIntervalSince1970)])
        XCTAssertEqual(state.jobs.status, "alarmSet")
        XCTAssertEqual(state.jobs.found, 1)
        XCTAssertEqual(state.jobs.enabled, 1)
        XCTAssertEqual(state.jobs.alarm, TestState.Alarm(at: at(600).timeIntervalSince1970, fireAt: at(660).timeIntervalSince1970, source: "launchd"))
        XCTAssertEqual(state.jobs.holds.map(\.source), ["launchd"])
        XCTAssertEqual(state.jobs.history, [TestState.Event(kind: "alarmSet", at: at(-5).timeIntervalSince1970)])
        XCTAssertEqual(state.notices.map(\.kind), ["finished", "waiting"], "The newest first")
        XCTAssertEqual(state.chimeAt, at(-3).timeIntervalSince1970)
        XCTAssertEqual(try JSONDecoder().decode(TestState.self, from: XCTUnwrap(state.encoded())), state)
    }

    func testAStopHasItsKindAsTheReason() {
        var input = fullInput()
        input.decision.headline = .safetyStop(.weakCharger(percent: 18))
        XCTAssertEqual(TestState(input).decision.headline, "safetyStop")
        XCTAssertEqual(TestState(input).decision.reason, "weakCharger")
        XCTAssertTrue(TestState(input).decision.stop)
        input.decision.headline = .safetyStop(.closedLid(.drop(points: 30)))
        input.safety = .closedLid(.drop(points: 30))
        XCTAssertEqual(TestState(input).decision.reason, "closedLidDrop")
        XCTAssertEqual(TestState(input).safety, "closedLidDrop")
        input.safety = .closedLid(.time(seconds: 3600))
        XCTAssertEqual(TestState(input).safety, "closedLidTime")
        input.closedLid = ClosedLidLimit()
        XCTAssertNil(TestState(input).closedLid, "No closed-lid period")
        input.decision.headline = .agentsStopped(.offline)
        XCTAssertEqual(TestState(input).decision.headline, "agentsStopped")
        XCTAssertEqual(TestState(input).decision.reason, "offline")
        XCTAssertFalse(TestState(input).decision.stop, "Other holds go on")
        input.offline = OfflineRule()
        XCTAssertEqual(TestState(input).network, TestState.Network(online: false, offlineSeconds: nil, limitSeconds: 600, agentsReleased: false))
        input.frame = nil
        XCTAssertNil(TestState(input).network)
        XCTAssertNil(TestState(input).power, "Nothing is known of the Mac before the first sample")
        XCTAssertNil(TestState(input).lid)
    }

    func testTheNoticeLogKeepsTheLastOnes() {
        var log = TestNoticeLog()
        for index in 0..<15 { log.note(.waiting, at: at(TimeInterval(index))) }
        XCTAssertEqual(log.events.count, TestNoticeLog.length)
        XCTAssertEqual(log.events.first?.at, at(14).timeIntervalSince1970)
    }

    func testTheGateHasANameForEachState() {
        var gate = WakeGate()
        XCTAssertEqual(gate.code, "open")
        gate.willSleep(awake: 10)
        XCTAssertEqual(gate.code, "sleepAnnounced")
        gate.sampled(awake: 12, slept: true)
        XCTAssertEqual(gate.code, "slept")
        gate.didWake(awake: 20)
        XCTAssertEqual(gate.code, "woke")
        gate.sampled(awake: 21, slept: false)
        XCTAssertEqual(gate.code, "open")
    }

    // MARK: Privacy

    /// The texts a field may hold when it is not a number or a flag. A
    /// key that is not here cannot hold a text.
    private static let texts: [String: Set<String>] = [
        "version": ["1.0.3"], "build": ["17"], "path": ["/Applications/agent caffeine.app"],
        "mode": Set(AwakeMode.allCases.map(\.rawValue)),
        "headline": ["working"], "helper": ["enabled"], "setup": ["ready"],
        "source": ["battery", "ac", "launchd", "crontab", "hermes"],
        "safety": ["batteryLow", "weakCharger", "tooHot", "closedLidTime", "closedLidDrop"],
        "stop": ["closedLidTime", "closedLidDrop"],
        "gate": ["open", "sleepAnnounced", "slept", "woke"],
        "id": ["claude", TestState.userAgentID, "0a1b2c3d"],
        "role": ["session", "engine", "helper", "maybeSession"],
        "state": ["working", "waiting", "idle"],
        "why": ["reportsBusy", "noActivity:3"],
        "level": ["state", "activity", "generic"],
        "hold": ["working", "waiting", "finished", "open"],
        "kind": Set(["timed", "command"] + JobEvent.Kind.allCases.map(\.rawValue) + TestNoticeKind.allCases.map(\.rawValue)),
        "status": ["alarmSet"],
    ]

    func testTheFileHoldsNoTextOfTheUser() throws {
        let known: Set<String> = [
            "v", "at", "app", "on", "pausedUntil", "reachableUntil", "mode", "decision", "flag",
            "power", "lid", "safety", "closedLid", "since", "heldSeconds", "percentAtStart", "limitSeconds", "limitDrop", "network", "online", "offlineSeconds", "agentsReleased", "gate", "agents", "holds", "jobs", "notices", "chimeAt",
            "version", "build", "path", "pid", "hold", "headline", "stop", "assertion", "wanted", "helper", "setup", "set",
            "source", "percent", "charging", "closed", "angle", "id", "role", "state", "why", "level", "kind", "start", "end",
            "status", "found", "enabled", "alarm", "fireAt", "history",
        ]
        var keys: Set<String> = []
        var strays: [String] = []
        func walk(_ value: Any, key: String) {
            if let object = value as? [String: Any] {
                keys.formUnion(object.keys)
                for (key, value) in object { walk(value, key: key) }
            } else if let list = value as? [Any] {
                list.forEach { walk($0, key: key) }
            } else if let text = value as? String, Self.texts[key]?.contains(text) != true {
                strays.append("\(key): \(text)")
            }
        }
        let state = TestState(fullInput())
        walk(try object(state), key: "")
        XCTAssertEqual(keys.subtracting(known), [], "A new key needs a rule for what it can hold")
        XCTAssertEqual(known.subtracting(keys), [], "Every known key is in the full file")
        XCTAssertEqual(strays, [], "A text that is not from a list of the app")
        let text = String(decoding: try XCTUnwrap(state.encoded()), as: UTF8.self)
        XCTAssertFalse(text.localizedCaseInsensitiveContains(Self.secret))
        XCTAssertFalse(text.contains("/Users/"))
    }

    /// No field of the file can take a text from outside: the model has
    /// texts only where the test above lists what they can be.
    func testEveryTextFieldOfTheModelHasARule() {
        var fields: Set<String> = []
        func walk(_ value: Any) {
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional {
                mirror.children.forEach { walk($0.value) }
                return
            }
            for child in mirror.children {
                if String(describing: type(of: child.value)).contains("String") { fields.insert(child.label ?? "") }
                walk(child.value)
            }
        }
        var input = fullInput()
        input.decision.headline = .safetyStop(.tooHot)
        walk(TestState(input))
        XCTAssertEqual(fields.subtracting(Self.texts.keys).subtracting(["reason"]), [])
        XCTAssertTrue(fields.contains("reason"), "The reason is the kind of a stop")
    }
}
